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

## SETTING STRING REPLACEMENT VARIABLE TO ISOLATE CLOUD.OPENSHIFT.COM CLAIM ONLY FOR LATER USE
export REPLACESTR=$(echo $PULL_SECRET| grep -oP '(?<=\{)"cloud.openshift.com"[^\}]+.,' )

## BACKING UP THE SECRET ORIGINALLY STORED IN OPENSHIFT-CONFIG NAMESPACE
ORIG_SECRET=$(oc get secrets pull-secret -n openshift-config -o template='{{index .data ".dockerconfigjson"}}' | base64 -d)
if [ -z $ORIG_SECRET ]; then echo "Please login into your cluster and relaunch the script so it can be executed properly"
	exit 2;
fi

echo $ORIG_SECRET|tee /tmp/pull-secret-ORIG.json /tmp/pull-secret-NEW.json

## REPLACE THE STRING 

sed -i -e 's/{"auths":{"arosvc.azurecr.io"/{"auths":{'''$REPLACESTR'''"arosvc.azurecr.io"/g' /tmp/pull-secret-NEW.json

## UPDATE PULL-SECRET ON THE CLUSTER

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/pull-secret-NEW.json

## DELETE THE INSIGHTS OPERATOR TO FORCE THE NEW CONFIGURATION

oc -n openshift-insights delete $(oc -n openshift-insights get pods -l app=insights-operator -o name)




