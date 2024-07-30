#!/usr/bin/env python

import sys
import json
import os

ZIP_EXTENSION = ".zip"

plugins_json_file = sys.argv[1]
output_file = sys.argv[2]

def get_file_name(path, name, type):
    return path + '/' + name + type

with open(plugins_json_file) as pf:
    plugins_object = json.load(pf)

with open(output_file, 'w+') as of:
    of.write('#!/usr/bin/env sh \n')

    confluentHubPlugins = plugins_object['ConfluentHubPlugins']
    if confluentHubPlugins is not None:
        for plugin in confluentHubPlugins:
            of.write(f"confluent-hub install {plugin['Name']} --no-prompt --worker-configs /dev/null --component-dir /mnt/plugins {plugin['ExtraArgs']} \n")

    urlPlugins = plugins_object['RemoteURLPlugins']
    if urlPlugins is not None:
        for plugin in urlPlugins:
            filename = get_file_name("/mnt/plugins", plugin['Name'], ZIP_EXTENSION)
            # download file
            of.write(f"wget {plugin['ArchivePath']} -O {filename} -P /mnt/plugins --no-check-certificate \n")

            # # verify checksum
            # sha512filename = get_file_name("/mnt/plugins", plugin['Name'], '.sha512')
            # of.write(f"echo {plugin['Checksum']} {filename} > {sha512filename} \n")
            # of.write(f"sha512sum --check {sha512filename} \n")
            # of.write(f"rm -f {sha512filename} \n")

            # install with confluent-hub
            of.write(f"confluent-hub install {filename} --no-prompt --worker-configs /dev/null --component-dir /mnt/plugins {plugin['ExtraArgs']} \n")
            of.write(f"rm -vf {filename} \n")
os.chmod(output_file, 0o755)
