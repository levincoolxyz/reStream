#!/bin/bash

# default values for arguments
ssh_host="10.11.99.1"      # assume reMarkable is connected through USB
landscape=false            # rotate window 90 deg cw for landscape view
output_path=-              # display output through ffplay
format=-                   # automatic output format

# start gui for options if the system has yad
if type yad >/dev/null && [ ! $(echo $DISPLAY) == "" ]; then
    output=$(yad --form --title "reMarkable streaming service" \
                 --field "ssh source:" "10.11.99.1" \
                 --align=right \
                 --field "ouput path:" "-" \
                 --align=right \
                 --field "format:" "-" \
                 --align=right \
                 --field "landscape view":CHK FALSE \
                 --align=center \
                 --fixed --timeout=60 --borders=10 --separator " ")
    if (( $? )); then exit 1; fi
    output=(${output})
    ssh_host=${output[0]}
    output_path=${output[1]}
    format=${output[2]}
    landscape=$(echo ${output[3]} | tr '[:upper:]' '[:lower:]')
else
# loop through arguments and process them
while [ $# -gt 0 ]; do
    case "$1" in
        -p| --portrait)
            landscape=false
            shift
            ;;
        -l| --landscape)
            landscape=true
            shift
            ;;
        -s| --source)
            ssh_host="$2"
            shift
            shift
            ;;
        -o| --output)
            output_path="$2"
            shift
            shift
            ;;
        -f| --format)
            format="$2"
            shift
            shift
            ;;
        -h| --help | *)
            echo "Usage: $0 [-pl] [-s <source>] [-o <output>] [-f <format>]"
            echo "Examples:"
            echo "  $0 -l                           # live view in landscape"
            echo "  $0 [-p]                         # live view in portrait"
            echo "  $0 -s 192.168.0.10              # connect to different IP"
            echo "  $0 -o reMarkable.mp4            # record to a file"
            echo "  $0 -o udp://dest:1234 -f mpegts # record to a stream"
            exit 1
            ;;
    esac
done
fi

# technical parameters
width=1408
height=1872
bytes_per_pixel=2
loop_wait="sleep 0.03"
# loglevel="info"
loglevel="error"
ssh_cmd() {
    ssh -o ConnectTimeout=1 "root@$ssh_host" "$@"
}

# check if we are able to reach the remarkable
if ! ssh_cmd true; then
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
# if ssh_cmd "[ -f \$HOME/lz4 ]"; then
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

# list of ffmpeg filters to apply
video_filters=""

# store extra ffmpeg arguments in $@
set --

# set each frame presentation time to the time it is received
video_filters="$video_filters,setpts=(RTCTIME - RTCSTART) / (TB * 1000000)"

# xor delta encoding & decoding with lz4 compression
compress_only="\$HOME/.bin/lz4" # lz4 binary path on reMarkable
decompress_only="lz4 -d" # lz4 binary command on host
xor="\$HOME/.bin/xorstream" # xorstream binary path on reMarkable
tmpfile="/tmp/fb_old" # path where the reference frame buffer is stored
compress="( $xor $tmpfile /dev/null e | $compress_only )"

# calculte how much bytes the window is
window_bytes="$(($width*$height*$bytes_per_pixel))" # 5271552

# rotate 90 degrees if landscape=true
landscape_param="$($landscape && echo '-vf transpose=1')"

# read the first $window_bytes of the framebuffer
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"

# loop that keeps on reading and compressing, to be executed remotely
read_loop="while $head_fb0; do $loop_wait; done | $compress"

# # store initial frame buffer and transfer to host (useless in 0.05 seconds)
# ssh_cmd "dd if=/dev/fb0 count=1 bs=$window_bytes of=$tmpfile 2>/dev/null"
# ssh_cmd "cat $tmpfile | $compress_only" | $decompress_only > $tmpfile
ssh_cmd "dd if=/dev/zero count=1 bs=$window_bytes of=$tmpfile 2>/dev/null"
dd if=/dev/zero count=1 bs=$window_bytes of=$tmpfile 2>/dev/null

set -- "$@" -vf "${video_filters#,}"

if [ "$output_path" = - ]; then
    output_cmd="ffplay -framedrop -sync ext -autoexit \
    -window_title reMarkable_streaming_service"
else
    output_cmd=ffmpeg

    if [ "$format" != - ]; then
        set -- "$@" -f "$format"
    fi

    set -- "$@" "$output_path"
fi

set -e # stop if an error occurs

# # original solution by rien
# # shellcheck disable=SC2086
# ssh_cmd "$read_loop" \
#     | $decompress \
#     | "$output_cmd" \
#         -vcodec rawvideo \
#         -loglevel "$loglevel" \
#         -f rawvideo \
#         -pixel_format gray16le \
#         -video_size "$width,$height" \
#         -i - \
#         "$@"

# adding gui related flares (no need to ctrl-c once ffplay quits) + some more flags
ssh_cmd "$read_loop" \
    | $decompress_only | xorstream $tmpfile /dev/null d \
    | ( $output_cmd \
        -fflags nobuffer -flags low_delay -probesize 32 \
        -vcodec rawvideo \
        -loglevel "$loglevel" \
        -f rawvideo \
        -pixel_format gray16le \
        -video_size "$width,$height" \
        $landscape_param \
        -i - \
        "$@" \
        ; echo "streaming service stopped."; kill -15 $(ps -elf | grep "while dd if=/dev/fb0" | grep "root@$ssh_host" | awk '{print $4}') )
