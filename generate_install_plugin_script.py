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

    of.write('echo HELLO \n')
os.chmod(output_file, 0o755)
