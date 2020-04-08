#!/bin/bash

# default values for arguments
ssh_host="10.11.99.1"      # remarkable connected trough USB
landscape=true             # rotate 90 degrees to the right

# start gui for options if the system has yad or zenity
if type yad >/dev/null && [ ! $(echo $DISPLAY) == "" ]; then
    output=$(yad --form --title "reMarkable streaming service" \
                 --field "ssh host" "10.11.99.1" \
                 --field "landscape view":CHK TRUE \
                 --fixed --timeout=60 --separator " ")
    # echo $output
    output=(${output})
    ssh_host=${output[0]}
    landscape=$(echo ${output[1]} | tr '[:upper:]' '[:lower:]')
    # echo $ssh_host
    # echo $landscape
elif type zenity >/dev/null && [ ! $(echo $DISPLAY) == "" ]; then
    ssh_host=$(zenity --title "reMarkable streaming service" \
                      --entry --text "ssh host address?" --entry-text "10.11.99.1" \
                       --timeout=60)
    zenity --question --title "reMarkable streaming service" \
           --text "view mode?" \
           --ok-label "Landscape" --cancel-label "Portrait" --timeout=10
    if (( ! $? )); then landscape=true; else landscape=false; fi
else
# loop through arguments and process them
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--portrait)
            landscape=false
            shift
            ;;
        -d|--destination)
            ssh_host="$2"
            shift
            shift
            ;;
        *)
            echo "Usage: $0 [-p] [-d <destination>]"
            exit 1
    esac
done
fi

# technical parameters
width=1408
height=1872
bytes_per_pixel=2
loop_wait=true
# loglevel=info
loglevel=error
ssh_cmd="ssh -o ConnectTimeout=1 "root@$ssh_host""

# check if we are able to reach the remarkable
if ! $ssh_cmd true; then
    echo "reMarkable unreachable @ $ssh_host"
    exit 1
fi

# fallback_to_gzip() {
#     echo "Falling back to gzip, your experience may not be optimal."
#     echo "Go to https://github.com/rien/reStream/#sub-second-latency for a better experience."
#     compress="gzip"
#     decompress="gzip -d"
#     sleep 2
# }

# check if lz4 is present on remarkable
# if $ssh_cmd "[ -f \$HOME/lz4 ]"; then
#     compress="\$HOME/lz4"
#     compress="/opt/bin/zstd --fast=200 -c"
# fi

# gracefully degrade to gzip if is not present on remarkable or host
# if [ -z "$compress" ]; then
#     echo "Your remarkable does not have lz4."
#     fallback_to_gzip
# elif ! which lz4; then
#     echo "Your host does not have lz4."
#     fallback_to_gzip
# else
#     decompress="lz4 -d"
#     decompress="zstd -d"
# fi

# xor delta encoding & decoding with lz4 compression
compress_only="\$HOME/lz4" # lz4 binary path on reMarkable
decompress_only="lz4 -d" # lz4 binary command on host
xor="\$HOME/.bin/xorstream" # xorstream binary path on reMarkable
tmpfile="/tmp/fb_old" # path where the reference frame buffer is stored
compress="( $xor $tmpfile /dev/null e | $compress_only )"

# calculte how much bytes the window is
window_bytes="$(($width*$height*$bytes_per_pixel))"
# window_bytes=5271552

# rotate 90 degrees if landscape=true
landscape_param="$($landscape && echo '-vf transpose=1')"

# read the first $window_bytes of the framebuffer
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"

# loop that keeps on reading and compressing, to be executed remotely
read_loop="while $head_fb0; do sleep 0.05; done | $compress"

# # store initial frame buffer and transfer to host (turns out unnecessary)
# $ssh_cmd "dd if=/dev/fb0 count=1 bs=$window_bytes of=$tmpfile"
# $ssh_cmd "cat $tmpfile | $compress_only" | $decompress_only > $tmpfile

set -e # stop if an error occurs

# # original solution by rien
# # shellcheck disable=SC2086
# # $ssh_cmd "$read_loop" \
# #     | $decompress \
# #     | ffplay -vcodec rawvideo \
# #              -loglevel "$loglevel" \
# #              -f rawvideo \
# #              -pixel_format gray16le \
# #              -video_size "$width,$height" \
# #              $landscape_param \
# #              -i -

# adding gui related flares (no need to ctrl-c once ffplay quits) + some ffmpeg flags
$ssh_cmd "$read_loop" \
    | $decompress_only | xorstream $tmpfile /dev/null d \
    | ( ffplay -fflags nobuffer -flags low_delay -framedrop \
             -probesize 32 -sync ext -autoexit \
             -window_title "reMarkable streaming service" \
             -vcodec rawvideo \
             -loglevel "$loglevel" \
             -f rawvideo \
             -pixel_format gray16le \
             -video_size "$width,$height" \
             $landscape_param \
             -i - \
    ; echo "streaming service stopped."; kill -15 $(ps -elf | grep "while dd if=/dev/fb0" | grep "root@$ssh_host" | awk '{print $4}') )
