#!/bin/bash
set -e

# Add local user
# Either use the LOCAL_USER_ID if passed in at runtime or
# fallback

USER_ID=${LOCAL_USER_ID:-9001}
GRP_ID=${LOCAL_GRP_ID:-9001}
ZEN_HOME="/mnt/zen"

getent group user > /dev/null 2>&1 || groupadd -g $GRP_ID user
id -u user > /dev/null 2>&1 || useradd --shell /bin/bash -u $USER_ID -g $GRP_ID -o -c "" -m user

LOCAL_UID=$(id -u user)
LOCAL_GID=$(getent group user | cut -d ":" -f 3)

if [ ! "$USER_ID" == "$LOCAL_UID" ] || [ ! "$GRP_ID" == "$LOCAL_GID" ]; then
  echo "Warning: User with differing UID "$LOCAL_UID"/GID "$LOCAL_GID" already exists, most likely this container was started before with a different UID/GID. Re-create it to change UID/GID."
fi

echo "Starting with UID/GID : "$(id -u user)"/"$(getent group user | cut -d ":" -f 3)

export HOME=/home/user

#Must have a zen config file
if [ ! -f "$ZEN_HOME/config/zen.conf" ]; then
  echo "No config found. Exiting."
  exit 1
else
  if [ ! -L $HOME/.zen ]; then
    ln -s $ZEN_HOME/config $HOME/.zen > /dev/null 2>&1 || true
  fi
fi

#zcash-params can be symlinked in from an external volume or created locally
if [ -d "$ZEN_HOME/zcash-params" ]; then
  if [ ! -L $HOME/.zcash-params ]; then
    echo "Symlinking external zcash-params volume..."
    ln -s $ZEN_HOME/zcash-params $HOME/.zcash-params > /dev/null 2>&1 || true
  fi
else
  echo "Using local zcash-params folder"
  mkdir -p $HOME/.zcash-params > /dev/null 2>&1 || true
fi

#data folder can be an external volume or created locally
if [ ! -d "$ZEN_HOME/data" ]; then
  echo "Using local data folder"
  mkdir -p $ZEN_HOME/data > /dev/null 2>&1 || true
else
  echo "Using external data volume"
fi

#link the secure node tracker config, bail if not present
#ls -lahR $ZEN_HOME/config
if [ -f "$ZEN_HOME/config/sec_tracker_config/stakeaddr" ]; then
  echo "Secure node config found OK - linking..."
  ln -s $ZEN_HOME/config/sec_tracker_config $ZEN_HOME/secnodetracker/config > /dev/null 2>&1 || true
else
  echo "No secure node config found. exiting"
  exit 1
fi

#Copy in any additional SSL trusted CA
if [ -d "$ZEN_HOME/config/root_certs" ]; then
  echo "Copying additional trusted root SSL certificates..."
  cp $ZEN_HOME/config/root_certs/* /usr/local/share/ca-certificates/ > /dev/null 2>&1 || true
  update-ca-certificates
fi

# Fix ownership of the created files/folders
chown -R user:user $HOME $HOME/.zcash-params $ZEN_HOME/zcash-params $ZEN_HOME

#Fetch zcash params before startup
/usr/local/bin/gosu user $ZEN_HOME/zcutil/fetch-params.sh


if [[ "$1" == start_secure_node ]]; then
  echo "Starting up Zen Daemon..."
  /usr/local/bin/gosu user zend &
  echo "Starting up Secure Node Tracker..."
  cd $ZEN_HOME/secnodetracker
  node app.js &
  tail -f /dev/null
else
  echo "Runnning command: $@"
  exec /usr/local/bin/gosu user "$@"
fi
