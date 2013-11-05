/* -*- Mode: C++; c-file-style: "gnu"; indent-tabs-mode:nil -*- */
/*
 * @copyright See LICENCE for copyright and license information.
 *
 * @author Ilya Moiseenko <iliamo@ucla.edu>
 */

#include "network-manager.h"

NetworkManager::NetworkManager()
{
    if (!QDBusConnection::systemBus().isConnected())
    {
        return;
    }

    autoconfigProcess = new QProcess(this);
    connect(autoconfigProcess,SIGNAL(finished(int)),this,SLOT(autoconfigFinished()));
    connect(autoconfigProcess, SIGNAL(error(QProcess::ProcessError)), this, SLOT(autoconfigFinished()));

    QDBusConnection::systemBus().connect("org.freedesktop.NetworkManager",
                                          "/org/freedesktop/NetworkManager",
                                          "org.freedesktop.NetworkManager",
                                          "StateChanged", this, SLOT(stateChanged(uint)));
}

void NetworkManager::stateChanged(uint state)
{
    if(state == NM_STATE_CONNECTED_GLOBAL)
        autoconfigDaemon();
}

void NetworkManager::autoconfigDaemon()
{
    if(IsAutoconfigRunning())
        return;

    isAutoconfigRunning = true;

    if(autoconfigProcess != NULL)
        autoconfigProcess->start(NDND_AUTOCONFIG_COMMAND);
}

void NetworkManager::autoconfigFinished()
{
    isAutoconfigRunning = false;
}

bool NetworkManager::IsAutoconfigRunning()
{
    return isAutoconfigRunning;
}

#if WAF
#include "network-manager.moc"
#include "network-manager.cpp.moc"
#endif
