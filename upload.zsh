#!/bin/zsh

threshold=${1:-100000}

echo "Emptying buffer..."
dfx canister call metarank emptyAssetBuffer

for file in ./art/*; do
    assetIndex=$(echo $file | sed -E "s/(\.\/art\/)([0-9]+)\.(webp)/\2/");\
    i=0
    bytes=$(od -v -tuC $file | sed -E "s/[0-9]+//")
    byteSize=${#bytes[@]}
    echo "Uploading asset #$assetIndex, size: $byteSize"
    while [ $i -le $byteSize ]; do
        chunk=${bytes[@]:$i:$threshold}
        chunkSize=${#chunk[@]}
        echo "chunk #$(($i/$threshold+1))..."
        dfx canister call metarank uploadAssetBuffer "( vec {\
            vec { $(for byte in $(echo $chunk | sed -E "s/[0-9]+//"); echo "$byte;") };\
        })"
        i=$(($i+$threshold))
    done
    echo "Finalizing asset $assetIndex..."
    dfx canister call metarank writeAssetBuffer "($assetIndex : nat, \"image/webp\")"
done