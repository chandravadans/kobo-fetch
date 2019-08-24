#!/bin/sh

BASE_DIR="${0%/*}"

#CONFIG params
LOG=/mnt/onboard/kobofetch_log.txt
DOWNLOAD_DIR=/mnt/onboard/download
CONFIG=${BASE_DIR}/kobofetch.config

DATE_CMD="date +%Y-%m-%d_%H:%M:%S"
CURL_CMD="${BASE_DIR}/curl --cacert \"${BASE_DIR}/ca-bundle.crt\" "

[ ! -e "$DOWNLOAD_DIR" ] && mkdir -p "$DOWNLOAD_DIR" >/dev/null 2>&1

if [ -f $LOG ];then
	rm $LOG
fi
echo "Log file created" > $LOG

log() {
	echo "$($DATE_CMD): ${*}" >> $LOG
}

get_remote_file() {
	linkLine="$1"
	localFile="$2"
	user="$3"    

	if [ "$user" = "" ]; then
	    curlCommand=$CURL_CMD
	else
	    curlCommand="$CURL_CMD -u $user: "
	fi
	    
	log "Curl command: $curlCommand"
	log "Writing $linkLine -> $localFile"

	remoteSize=$($curlCommand -k -L --silent --head "$linkLine" | tr A-Z a-z | sed -n 's/^content-length\: \([0-9]*\).*/\1/p')
	log "Remote size: $remoteSize"
	if [ -f "$localFile" ]; then
	  localSize=$(stat -c%s "$localFile")
	else
	  localSize=0
	fi
	if [ "$remoteSize" = "" ]; then
	  remoteSize=1
	fi
	if [ $localSize -ge $remoteSize ]; then
	  echo "File exists: skipping"
	else
	  $curlCommand -k --silent -C - -L -o "$localFile" "$linkLine" # try resuming
	  if [ $? -ne 0 ]; then
	    log "Error resuming: redownloading file"
	    $curlCommand -k --silent -L -o "$localFile" "$linkLine" # restart download
	  fi
	fi
	log "Fetched remote file"
}

get_dropbox_files() {
	baseURL="$1"
	outDir="$2"

	baseURL=$(echo "$baseURL" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

	# get directory listing
	log "Getting $baseURL"
	# get directory listing
	$CURL_CMD -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.89 Safari/537.36" -k -L --silent "$baseURL" | # get listing. Need to specify a user agent, otherwise it will download the directory
	grep -Eo 'previews\.dropboxusercontent\.com.*' | 
	grep -Eo 'https?://www.dropbox.com/sh/[^\"]*' | # find links
	while read linkLine
	do
	  if [ "$linkLine" = "$baseURL" ]
	  then
	    continue
	  fi
	  # process line 
	  outFileName=$(echo "$linkLine" | sed -e 's|.*/\(.*\)?dl=.*|\1|')
	  localFile="$outDir/$outFileName"
	  get_remote_file "$linkLine" "$localFile"
	done
}

#check internet connection
log "Waiting for network"
r=1;i=0
while [ $r != 0 ]; do
  if [ $i -gt 60 ]; then
    ping -c 1 -w 3 dropbox.com
    log "Error! no connection detected, exiting" 
    exit 1
  fi
  ping -c 1 -w 3 dropbox.com >/dev/null 2>&1
  r=$?
  if [ $r != 0 ]; then sleep 1; fi
  i=$(($i + 1))
done

log "Connectivity check passed"

while read url; do
  log "Reading $url"
  if echo "$url" | grep -q '^#'; then
    # Comment
    log "Skipping $url"
  else
      log "Getting dropbox files"
      get_dropbox_files "$url" "$DOWNLOAD_DIR"
  fi
done < $CONFIG

log "Done!"
