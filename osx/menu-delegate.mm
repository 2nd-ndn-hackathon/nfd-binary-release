/* -*- Mode: obj; c-file-style: "gnu"; indent-tabs-mode:nil -*- */
/*
 * @copyright See LICENCE for copyright and license information.
 *
 * @author Alexander Afanasyev <alexander.afanasyev@ucla.edu>
 * @author Ilya Moiseenko <iliamo@ucla.edu>
 */

#include "config.h"
#import "menu-delegate.h"
#import "ndnd-status-operation.h"

@implementation MenuDelegate

-(id)init
{
  if (![super init]) {
    return nil;
  }

  m_autoconfInProgress = false;
  m_operationQueue = [[NSOperationQueue alloc] init];
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  m_daemonStarted = false; 
  allowSoftwareUpdates = true;
  enableHubDiscovery = true;

  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  m_connectedIcon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"FlatConnected" ofType:@"png"]];
  m_disconnectedIcon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:@"FlatDisconnected" ofType:@"png"]];
  m_statusXslt = [NSData dataWithContentsOfFile:[bundle pathForResource:@"status" ofType:@"xslt"]];
  m_statusToFibXslt = [NSData dataWithContentsOfFile:[bundle pathForResource:@"status-to-fib" ofType:@"xslt"]];
  
  [NSTimer scheduledTimerWithTimeInterval: 1.0
           target: self
           selector:@selector(onTick:)
           userInfo: nil
           repeats:YES];
  [self updateStatus];

  m_systemEvents = [[SystemEvents alloc] init];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
  [m_systemEvents disable];
}

-(void)awakeFromNib
{
  statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  [statusItem setMenu:statusMenu];
  [statusItem setToolTip:@"NDN Control Center"];
  [statusItem setEnabled:YES];
  [statusItem setHighlightMode:YES];
  //[statusItem setTarget:self];

  [statusItem setTitle:@""];
  [statusItem setImage:m_disconnectedIcon];
  
  [connectionStatus setView: connectionStatusView];
  [connectionStatus setTarget:self];
  
  [daemonStatus setView: daemonStatusView];
  [daemonStatus setTarget:self];
}

-(IBAction)openDaemonStatus:(id)sender
{
}

-(IBAction)showExitConfirmationWindow:(id)sender
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert addButtonWithTitle:@"Yes"];
  [alert addButtonWithTitle:@"No"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert setMessageText:@"Shutdown NDN daemon as well?"];
  [alert setInformativeText:@"All NDN operations will be become unavailable."];
  [alert setAlertStyle:NSCriticalAlertStyle];
  [alert setShowsSuppressionButton: YES];

  NSInteger res = [alert runModal];
  if (res == NSAlertFirstButtonReturn) {
    // "YES" stop ndnd
    [m_operationQueue cancelAllOperations];

    [m_operationQueue addOperationWithBlock:^{
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath: @NDND_STOP_COMMAND];
        [task launch];
        [task waitUntilExit];
      }];

    [m_operationQueue waitUntilAllOperationsAreFinished];
    [NSApp terminate:self];
  } else if (res == NSAlertSecondButtonReturn) {
    // "NO" terminate app but keep ndnd running
    [m_operationQueue cancelAllOperations];
    [NSApp terminate:self];
  }
}

-(void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item
{
  if( ([item view]!=nil) && (item == daemonStatus) )
  {
    NSView *view = [item view];
    
    [statusPopover showRelativeToRect:[view bounds]
                   ofView:view
                   preferredEdge:NSMinXEdge];
  }
  else
  {
    [statusPopover performClose:nil];
  }
}

-(void)onTick:(NSTimer *)timer
{
  [self updateStatus];
}

-(void)updateStatus
{
  NSOperation *operation = [[NdndStatusOperation alloc] initWithDelegate:self];
  [m_operationQueue addOperation:operation];
}

-(void)updateStatusWithDependency:(NSOperation*)dependency
{
  NSOperation *operation = [[NdndStatusOperation alloc] initWithDelegate:self];
  [operation addDependency:dependency];

  [m_operationQueue addOperation:dependency];
  [m_operationQueue addOperation:operation];
}

- (void)statusUpdated:(NSXMLDocument*)document
{
  if (!m_daemonStarted) {
    m_daemonStarted = true;
    [connectionStatusText setStringValue:@"Active"];
    
    [statusItem setImage:m_connectedIcon];
  }

  NSXMLDocument *statusXml = [document objectByApplyingXSLT:m_statusXslt
                              arguments:nil
                              error:nil];

  NSXMLDocument *statusFibXml = [document objectByApplyingXSLT:m_statusToFibXslt
                                 arguments:nil
                                 error:nil];

  m_statusString = [[NSAttributedString alloc]initWithHTML:[statusXml XMLData] documentAttributes:NULL];
  [daemonStatusHtml setAttributedStringValue:m_statusString];

  [preferencesDelegate updateFibStatus:statusFibXml];

  NSArray *autoconf = [[statusFibXml rootElement] nodesForXPath:@"//fib/prefix[text()='ndn:/autoconf-route']" error:nil];
  if ([autoconf count] == 0)
    {
      [self restartDaemon:nil];
    }
}

- (void)statusUnavailable:(id)none
{
  // try start ndnd if it is not started yet
  if (m_daemonStarted) {
    m_daemonStarted = false;
    
    [connectionStatusText setStringValue:@"Starting..."];
    
    [statusItem setImage:m_disconnectedIcon];
  }

  [daemonStatusHtml setStringValue:@""];
  [preferencesDelegate updateFibStatus:nil];

  m_autoconfInProgress = true;
  
  NSOperation *startOp = [NSBlockOperation blockOperationWithBlock:^{
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: @NDND_START_COMMAND];
      [task launch];
    }];

  NSOperation *autoconfOp = [NSBlockOperation blockOperationWithBlock:^{
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: @NDND_AUTOCONFIG_COMMAND];
      [task launch];
      [task waitUntilExit];

      m_autoconfInProgress = false;
    }];

  [autoconfOp addDependency:startOp];

  [m_operationQueue addOperation:startOp];
  [m_operationQueue addOperation:autoconfOp];
}

-(void)restartDaemon:(id)none
{
  if (m_autoconfInProgress)
    return;

  NSLog (@"No automatically detected route configured, trying to get one");
  
  m_autoconfInProgress = true;
  [m_operationQueue addOperationWithBlock:^{
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: @NDND_AUTOCONFIG_COMMAND];
      [task launch];
      [task waitUntilExit];

      m_autoconfInProgress = false;
    }];
}

@end
