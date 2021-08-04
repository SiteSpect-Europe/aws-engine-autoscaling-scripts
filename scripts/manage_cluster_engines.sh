#!/usr/bin/env bash

PID=/home/sitespect/engine_up_cron
if [[ -f ${PID} ]]; then
    echo "Already running"
    exit 1
fi

touch ${PID}

ENGINE_ASG=stg-sitespect-engine-ec2
ids=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names stg-sitespect-engine-ec2 --query "AutoScalingGroups[*].Instances[*].InstanceId" --output text)

if [[ -n $ids ]]
then
    for engine in $ids
    do
        engines+=$(aws ec2 describe-instances --instance-ids ${engine} --query "Reservations[*].Instances[*].PrivateIpAddress" --output text)
        engines+=" "
    done
fi

for engine in ${engines};
do
    exists=$(/opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --listengines | grep -c ${engine})
    if [[ ${exists} -eq 0 ]]; then
        echo "Adding ${engine} to cluster"
        /opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --addengine ${engine} --platform centos --servergroup 1 || continue
	      sleep 3
        echo "Putting ${engine} online"
        node_id=$(/opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --listengines | grep ${engine} | awk '{print $1}') || continue
        /opt/sitespect/lib/perl/SiteSpect/Util/manage_cluster.pl --setnodestatus up --node ${node_id} || continue
        /opt/sitespect/lib/perl/SiteSpect/Util/manage_engine_nodes.pl -c bypass --param action=restore --node ${node_id}
    else
        echo "${engine} already part of cluster"
    fi
done

rm -f ${PID}
