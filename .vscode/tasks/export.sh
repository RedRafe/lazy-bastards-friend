#!/bin/bash

folder=($(jq -r '.name' 'info.json'))
version=($(jq -r '.version' 'info.json'))

cd ..

rm "../${folder}_${version}.zip"

zip -r "../${folder}_${version}.zip" "${folder}" -x "*/.vscode/**\*" -x "*.git*" -x "*/\.*" -x "*/archive/*"
