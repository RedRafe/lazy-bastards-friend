#!/bin/bash

folder=($(jq -r '.name' 'info.json'))
version=($(jq -r '.version' 'info.json'))

cd ..

rm "../${folder}.zip"

rm -r "../${folder}_${version}"

rm "../${folder}_${version}.zip"

