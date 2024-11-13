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


# ASK FOR TELEMETRY AND OCM REGISTERING CONSENT

while true;	do
	read -p "Do you want to register your ARO cluster in OCM and send Red Hat telemetry data as well? (yes|no): " answer_ocm
	case ${answer_ocm} in
		yes) break;;
		no) break;;
		*) echo "Invalid data, please enter yes or no.";sleep 0.5;clear;;
	esac
done

## TOKEN CHECK
if [[ -z $OFFLINE_ACCESS_TOKEN ]];
then echo "Please go to https://console.redhat.com/openshift/token/show and copy the offline token so you can re-launch this script properly."
	exit 2
fi

## ACCESS TO THE SSO AND THEN DOWNLOAD THE PULL SECRET
export BEARER_TOKEN=$(curl \
--silent \
--data-urlencode "grant_type=refresh_token" \
--data-urlencode "client_id=cloud-services" \
--data-urlencode "refresh_token=${OFFLINE_ACCESS_TOKEN}" \
https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token | \
jq -r .access_token)

export PULL_SECRET=$(curl -X POST https://api.openshift.com/api/accounts_mgmt/v1/access_token --header "Content-Type:application/json" --header "Authorization: Bearer $BEARER_TOKEN")

## VARIABLES FOR THE SECRET FILENAMES
ORIG_SECRET=/tmp/pull-secret-ORIG_${TIMESTAMP}.json
NEW_SECRET=/tmp/pull-secret-NEW_${TIMESTAMP}.json

## BACKING UP THE SECRET ORIGINALLY STORED IN OPENSHIFT-CONFIG NAMESPACE
oc get secrets pull-secret -n openshift-config -o template='{{index .data ".dockerconfigjson"}}' | base64 -d |tee ${ORIG_SECRET}

if [ ! -s $ORIG_SECRET ]; then echo "Backup secret file is empty, please login into your cluster and/or check if the secret exists then retry executing the script."
	exit 2;
fi

## VARIABLES FOR THE JSON OBJECTS OF EACH ENDPOINT
export VALUE_CLOUD=$(echo $PULL_SECRET| jq -r '.auths."cloud.openshift.com"' )
export VALUE_REGISTRY_1=$(echo $PULL_SECRET| jq -r '.auths."registry.connect.redhat.com"' )
export VALUE_REGISTRY_2=$(echo $PULL_SECRET| jq -r '.auths."registry.redhat.io"' )
export VALUE_QUAY=$(echo $PULL_SECRET| jq -r '.auths."quay.io"' )


## REPLACE THE STRING ACCORDINGLY TO THE USER'S PREFERENCE
if [[ "$answer_ocm" == "yes" ]];then
		echo "Now adding your  values to the secret pulled from the cluster to build the new file"
		jq -c '.auths."registry.connect.redhat.com" = '''"${VALUE_REGISTRY_1}"''' | .auths."registry.redhat.io" = '''"${VALUE_REGISTRY_2}"''' | .auths."quay.io" = '''"${VALUE_QUAY}"''' | .auths."cloud.openshift.com" |= '''"${VALUE_CLOUD}"''' ' $ORIG_SECRET| tee ${NEW_SECRET}
	else 
		# IN THIS CASE THE OCM AND TELEMETRY CONSENT SECRET WON'T BE CONFIGURED	
		echo "Now replacing the cloud.openshift.com values in the secret pulled from the cluster to build the new file"
		jq -c '.auths."registry.connect.redhat.com" = '''"${VALUE_REGISTRY_1}"''' | .auths."registry.redhat.io" = '''"${VALUE_REGISTRY_2}"''' | .auths."quay.io" = '''"${VALUE_QUAY}"''' ' $ORIG_SECRET| tee ${NEW_SECRET}
fi



jq '.' $NEW_SECRET

## FINAL CHECK AND DATA VALIDATION BEFORE EVERYTHING 
while true;do
	read -p "Are you okay with the json file that will be uploaded? :" final_answer
	case $final_answer in
		yes) break;;
		no) echo "Exiting by user's choice. If you want to manually edit and upload the generated secret do as follows:"
			echo 'export NEW_SECRET="'''${NEW_SECRET}'''"';
			echo 'oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/pull-secret-NEW_${TIMESTAMP}.json'
			echo 'oc -n openshift-insights delete $(oc -n openshift-insights get pods -l app=insights-operator -o name)'
			exit 2;;
		*)sleep 0.5;clear;jq '.' $NEW_SECRET;;
	esac
	done

## IN CASE OF POSITIVE FEEDBACK AFTER THE FINAL CHECK
if [[ "${final_answer}" == "yes"]];then

## UPDATE PULL-SECRET ON THE CLUSTER

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/pull-secret-NEW_${TIMESTAMP}.json

## DELETE THE INSIGHTS OPERATOR TO FORCE THE ROLLOUT OF THE PODS TO READ THE NEW CONFIGURATION

oc -n openshift-insights delete $(oc -n openshift-insights get pods -l app=insights-operator -o name)
fi