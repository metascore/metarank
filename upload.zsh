#!/bin/zsh

threshold=${1:-100000}
network=${2:-local}

echo "Emptying buffer..."
dfx canister --network $network call metarank emptyAssetBuffer

for file in ./art/*; do
    assetIndex=$(echo $file | sed -E "s/(\.\/art\/)([0-9]+)\.(webp)/\2/");\
    i=0
    byteSize=${#$(od -An -v -tuC $file)[@]}
    echo "Uploading asset #$assetIndex, size: $byteSize"
    while [ $i -le $byteSize ]; do
        echo "chunk #$(($i/$threshold+1))..."
        dfx canister --network $network call metarank uploadAssetBuffer "( vec {\
            vec { $(for byte in ${(j:;:)$(od -An -v -tuC $file)[@]:$i:$threshold}; echo "$byte;") };\
        })"
        i=$(($i+$threshold))
    done
    echo "Finalizing asset $assetIndex..."
    dfx canister --network $network call metarank writeAssetBuffer "($assetIndex : nat, \"image/webp\")"
done