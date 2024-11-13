#!/usr/bin/env bash
######################################################################################################################
##  +-----------------------------------+-----------------------------------+
##  |                                                                       |
##  | Copyright (c) 2023-2024, Marco Placidi<mplacidi@redhat.com>.          |
##  |                                                                       |
##  | This program is free software: you can redistribute it and/or modify  |
##  | it under the terms of the GNU General Public License as published by  |
##  | the Free Software Foundation, either version 3 of the License, or     |
##  | (at your option) any later version.                                   |
##  |                                                                       |
##  | This program is distributed in the hope that it will be useful,       |
##  | but WITHOUT ANY WARRANTY; without even the implied warranty of        |
##  | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         |
##  | GNU General Public License for more details.                          |
##  |                                                                       |
##  | You should have received a copy of the GNU General Public License     |
##  | along with this program. If not, see <http://www.gnu.org/licenses/>.  |
##  |                                                                       |
#   |  About the author:                                                    |
#   |                                                                       |
#   |  Owner:   Marco Placidi                                               |
#   |  GitHub:  https://github.com/demon86rm                                |
##  |                                                                       |
##  +-----------------------------------------------------------------------+
#
#
# DESCRIPTION
#
# This script is made by just a couple of lines of Bash to automate the pull-secret patching in your ARO cluster. Therefore you'll be able to get the Insights for your cluster and have it registered in OCM (https://cloud.redhat.com/openshift) as well.
# In order to run smoothly the script is necessary that you have the OCM token to let the script download the pull-secret for you.
#
# 
# VARIABLES
#
## OFFLINE_ACCESS_TOKEN
# As described in https://access.redhat.com/solutions/4844461, a token is needed if you didn't already downloaded the pull-secret in first place while executing this script. 

OFFLINE_ACCESS_TOKEN=$1
TIMESTAMP=$(date +%Y.%m.%d_%H%M%S)

## TOKEN CHECK
if [[ -z $OFFLINE_ACCESS_TOKEN ]];
then echo "Please go to https://console.redhat.com/openshift/token/show and copy the offline token so you can re-launch this script properly."
	exit 2
fi

## PULL SECRET DOWNLOAD
export BEARER_TOKEN=$(curl \
--silent \
--data-urlencode "grant_type=refresh_token" \
--data-urlencode "client_id=cloud-services" \
--data-urlencode "refresh_token=${OFFLINE_ACCESS_TOKEN}" \
https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token | \
jq -r .access_token)

export PULL_SECRET=$(curl -X POST https://api.openshift.com/api/accounts_mgmt/v1/access_token --header "Content-Type:application/json" --header "Authorization: Bearer $BEARER_TOKEN")

## BACKING UP THE SECRET ORIGINALLY STORED IN OPENSHIFT-CONFIG NAMESPACE
ORIG_SECRET=/tmp/pull-secret-ORIG_${TIMESTAMP}.json
NEW_SECRET=/tmp/pull-secret-NEW_${TIMESTAMP}.json
oc get secrets pull-secret -n openshift-config -o template='{{index .data ".dockerconfigjson"}}' | base64 -d |tee ${ORIG_SECRET}

if [ ! -s $ORIG_SECRET ]; then echo "Backup secret file is empty, please login into your cluster and/or check if the secret exists then retry executing the script."
	exit 2;
fi

## CHECK IF THE SECRET WAS ALREADY MODIFIED
export FILECHECK=$(grep -oP '(?<=\{)"cloud.openshift.com"[^\}]+.,' ${ORIG_SECRET};echo $?)
export VALUE=$(echo $PULL_SECRET| jq -r '.auths."cloud.openshift.com"' )

## REPLACE THE STRING ACCORDINGLY 
if [[ ${FILECHECK} != "0" ]]; then
		echo "Now adding the cloud.openshift.com values to the secret pulled from the cluster to build the new file"
		jq -c '.auths."cloud.openshift.com" |= '''"${VALUE}"''' + .' $ORIG_SECRET| tee ${NEW_SECRET}
	else 
			
		echo "Now replacing the cloud.openshift.com values in the secret pulled from the cluster to build the new file"
		jq '.auths."cloud.openshift.com" = '''"${VALUE}"''' ' $ORIG_SECRET| tee ${NEW_SECRET}
fi

## UPDATE PULL-SECRET ON THE CLUSTER

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/pull-secret-NEW_${TIMESTAMP}.json

## DELETE THE INSIGHTS OPERATOR TO FORCE THE NEW CONFIGURATION

oc -n openshift-insights delete $(oc -n openshift-insights get pods -l app=insights-operator -o name)
