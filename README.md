# insight-my-aro
Simple bash script that will help you add your "cloud.openshift.com" pull-secret claim to the one in the openshift-config namespace in order to let you enable the insights as well as registering your ARO cluster in OCM.

# instructions for a proper execution
1. git clone https://github.com/CSA-RH/insight-my-aro.git
2. cd insight-my-aro
3. oc login into your ARO cluster
4. Download your OCM API token from https://cloud.redhat.com/openshift/token/show
5. Copy the token in your clipboard
6. ./insight-my-aro.sh ${your_token}
7. Sit back and relax

If you want to roll-back because something is f*ed up, you'll find a copy of both the original/untouched pull-secret as well as the updated one in your /tmp folder, the filenames are respectively:
1. /tmp/pull-secret-ORIG_${TIMESTAMP}.json
2. /tmp/pull-secret-NEW_${TIMESTAMP}.json

The ${TIMESTAMP} variable is valued after the "date +%Y.%m.%d_%H%M%S" command issued at the moment of the script's execution.
