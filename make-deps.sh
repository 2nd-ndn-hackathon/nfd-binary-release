#!/usr/bin/env bash

NDN_CXX_COMMIT=${NDN_CXX_COMMIT:-master}
NFD_COMMIT=${NFD_COMMIT:-master}

GIT=${GIT:-https://github.com/named-data}

mkdir build 2>/dev/null || true
path="$(pwd)"

pushd build
wget https://github.com/sparkle-project/Sparkle/releases/download/1.14.0/Sparkle-1.14.0.tar.bz2
mkdir Sparkle-1.14 || true
pushd Sparkle-1.14
tar xf ../Sparkle-1.14.0.tar.bz2
popd
mv Sparkle-1.14/Sparkle.framework .
popd

#######################################

rm -Rf build/ndn-cxx
git clone ${GIT}/ndn-cxx build/ndn-cxx
pushd build/ndn-cxx
git checkout ${NDN_CXX_COMMIT}

patch -p1 <<EOF
diff --git a/src/transport/unix-transport.cpp b/src/transport/unix-transport.cpp
index 6b86a34..e72170e 100644
--- a/src/transport/unix-transport.cpp
+++ b/src/transport/unix-transport.cpp
@@ -72,7 +72,7 @@ UnixTransport::getDefaultSocketName(const ConfigFile& config)
     }
 
   // Assume the default nfd.sock location.
-  return "/var/run/nfd.sock";
+  return "/tmp/nfd.sock";
 }
 
 shared_ptr<UnixTransport>
EOF

./waf configure --prefix="${path}/build/deps" \
                --sysconfdir="/Applications/NDN.app/Contents/etc"
./waf build
./waf install
popd

####################################

rm -Rf build/NFD
git clone ${GIT}/NFD build/NFD
pushd build/NFD
git checkout ${NFD_COMMIT}
git submodule update --init
PKG_CONFIG_PATH="${path}/build/deps/lib/pkgconfig:${PKG_CONFIG_PATH}" \
               ./waf configure --prefix="${path}/build/deps" \
                               --sysconfdir="/Applications/NDN.app/Contents/etc"
./waf build
./waf install
popd

PKG_CONFIG_PATH="${path}/build/deps/lib/pkgconfig:${PKG_CONFIG_PATH}" \
               ./waf configure
