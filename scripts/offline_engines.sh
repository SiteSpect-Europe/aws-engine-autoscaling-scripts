#!/usr/bin/env bash

PID=/home/sitespect/engine_down_cron
if [[ -f ${PID} ]]; then
    echo "Already running"
    exit 1
fi

touch ${PID}

ENGINE_ASG=stg-sitespect-engine-ec2
ids=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names stg-sitespect-engine-ec2 --query "AutoScalingGroups[*].Instances[*].InstanceId" --output text)
if [[ -n ${ids} ]]; then
    for engine in ${ids}
    do
        engines+=$(aws ec2 describe-instances --instance-ids ${engine} --query "Reservations[*].Instances[*].PrivateIpAddress" --output text)
        engines+=" "
    done
fi

for engine_offline in $(/opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --listengines | grep SG1 | awk '{print $3}');
do
   if [[ ! ${engines} =~ ${engine_offline} ]];
   then
       echo "Taking ${engine_offline} offline"
       node_id=$(/opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --listengines | grep ${engine_offline} | awk '{print $1}')
       /opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --deleteengine ${node_id}
   fi
done

rm -f ${PID}
