#!/bin/zsh

threshold=100000

for file in ./art/*; do
    contentType="image/webp"
    i=0
    bytes=$(od -v -tuC $file | sed -E "s/[0-9]+//")
    byteSize=${#bytes[@]}
    echo "Image size: $byteSize"
    while [ $i -le $byteSize ]; do
        chunk=${bytes[@]:$i:$threshold}
        chunkSize=${#chunk[@]}
        echo "Uploading chunk, size: $chunkSize"
        dfx canister call metarank uploadAssetBuffer "( vec {\
            vec { $(echo ${(j:;:)chunk}) };\
        })"
        i=$(($i+$threshold))
    done
done