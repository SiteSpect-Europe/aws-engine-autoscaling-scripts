export PATH="${BATS_TEST_DIRNAME}/../scripts:${BATS_TEST_DIRNAME}/fixtures/bin:${PATH}"

# Put pidfile stuff in this dir
for dir in "$BATS_TEST_DIRNAME" "${TMPDIR:-/tmp}"; do
    if [[ -w "$dir" ]] && tmpfile="$(mktemp "${dir}/.write-test.XXXXXXXXXX")"; then
        rm -f "$tmpfile"
        MCE_PIDFILE_BASE="${dir}/.mce"
    fi
done

if [[ -z "${MCE_PIDFILE_BASE:-}" ]]; then
    printf 1>&2 -- '%s: cannot find a writeable path for the mce PID file; please specify a PID file template in a writeable path via the MCE_PIDFILE_BASE environment variable.\n'
    exit 75 # EX_TEMPFAIL
fi

export MCE_PIDFILE_BASE

ACTIVE_REGISTERED_IP=1.1.1.1
ACTIVE_REGISTERED_NODE_ID=1
ACTIVE_REGISTERED_INSTANCE_ID=1001

ACTIVE_UNREGISTERED_IP=2.2.2.2
ACTIVE_UNREGISTERED_NODE_ID=2
ACTIVE_UNREGISTERED_INSTANCE_ID=1002

INACTIVE_REGISTERED_IP=3.3.3.3
INACTIVE_REGISTERED_NODE_ID=3
INACTIVE_REGISTERED_INSTANCE_ID=1003

INACTIVE_UNREGISTERED_IP=4.4.4.4
INACTIVE_UNREGISTERED_NODE_ID=4
INACTIVE_UNREGISTERED_INSTANCE_ID=1004

run_mce() {
    ACTIVE_REGISTERED_ENGINES="${ACTIVE_REGISTERED_IP}=${ACTIVE_REGISTERED_NODE_ID}=${ACTIVE_REGISTERED_INSTANCE_ID}" \
    INACTIVE_REGISTERED_ENGINES="${INACTIVE_REGISTERED_IP}=${INACTIVE_REGISTERED_NODE_ID}=${INACTIVE_REGISTERED_INSTANCE_ID}" \
    ACTIVE_UNREGISTERED_ENGINES="${ACTIVE_UNREGISTERED_IP}=${ACTIVE_UNREGISTERED_NODE_ID}=${ACTIVE_UNREGISTERED_INSTANCE_ID}" \
    INACTIVE_UNREGISTERED_ENGINES="${INACTIVE_UNREGISTERED_IP}=${INACTIVE_UNREGISTERED_NODE_ID}=${INACTIVE_UNREGISTERED_INSTANCE_ID}" \
    MCE_SERVERGROUP=10 \
    MCE_AUTO_SCALING_GROUP_NAME=bar \
    run mce --verbose "$@"
}

run_mce_fail_aws_autoscaling_describe_autoscaling_groups() {
    AWS_AUTO_SCALING_DESCRIBE_AUTO_SCALING_GROUPS_EXIT_STATUS=1 run_mce "$@"
}

run_mce_fail_aws_ec2_describe_instances() {
    AWS_EC2_DESCRIBE_INSTANCES_EXIT_STATUS=1 run_mce "$@"
}

run_mce_empty_aws_autoscaling_describe_autoscaling_groups() {
    AWS_AUTO_SCALING_DESCRIBE_AUTO_SCALING_GROUPS_EMPTY=1 run_mce "$@"
}

run_mce_empty_aws_ec2_describe_instances() {
    AWS_EC2_DESCRIBE_INSTANCES_EMPTY=1 run_mce "$@"
}

run_mce_fail_mysql_nodes_in_servergroup() {
    MYSQL_NODES_IN_SERVERGROUP_EXIT_STATUS=1 run_mce "$@"
}

run_mce_fail_mysql_fetch_node_id_from_ipv4() {
    MYSQL_FETCH_NODE_ID_FROM_IPV4_EXIT_STATUS=1 run_mce "$@"
}

run_mce_aws_take_too_long() {
    MCE_AWS_CLI_GLOBAL_TIMEOUT=0.1s AWS_FORCED_TIMEOUT=1s run_mce "$@"
}

run_mce_cluster_actions_take_too_long() {
    MCE_AWS_CLI_GLOBAL_TIMEOUT=0.2s \
    MANAGE_CLUSTER_FORCED_TIMEOUT=0.5s \
    MANAGE_ENGINE_NODES_FORCED_TIMEOUT=0.5s \
    run_mce "$@"
}

@test 'adds active unregistered engines' {
    run_mce online

    (( status == 0 ))

    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" == *'manage_cluster.pl'*'addengine'*"${ACTIVE_UNREGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_UNREGISTERED_IP}"* ]]

    [[ "$output" == *'manage_cluster.pl'*'setnodestatus'*'up'* ]]

    [[ "$output" == *'manage_engine_nodes.pl'*'bypass'*'action=restore'* ]]
}

@test 'deletes inactive registered engines' {
    run_mce offline

    (( status == 0 ))

    [[ "$output" != *'manage_cluster.pl'*'deleteengine'*"$ACTIVE_REGISTERED_NODE_ID"* ]]
    [[ "$output" != *'manage_cluster.pl'*'deleteengine'*"$ACTIVE_UNREGISTERED_NODE_ID"* ]]
    [[ "$output" == *'manage_cluster.pl'*'deleteengine'*"$INACTIVE_REGISTERED_NODE_ID"* ]]
    [[ "$output" != *'manage_cluster.pl'*'deleteengine'*"$INACTIVE_UNREGISTERED_NODE_ID"* ]]
}

@test 'exits nonzero (but still registers engines) if listing autoscaling groups fails' {
    run_mce_fail_aws_autoscaling_describe_autoscaling_groups online

    (( status != 0 ))

    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" == *'manage_cluster.pl'*'addengine'*"${ACTIVE_UNREGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_UNREGISTERED_IP}"* ]]

    [[ "$output" == *'manage_cluster.pl'*'setnodestatus'*'up'* ]]

    [[ "$output" == *'manage_engine_nodes.pl'*'bypass'*'action=restore'* ]]
}

@test 'issues a warning (but exits with zero) if no autoscaling groups were listed' {
    run_mce_empty_aws_autoscaling_describe_autoscaling_groups online

    (( status == 0 ))

    [[ "$output" == *'there are no instance IDs associated with auto-scaling group'*'(is this the correct auto-scaling group?)'* ]]

    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_UNREGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_UNREGISTERED_IP}"* ]]

    [[ "$output" != *'manage_cluster.pl'*'setnodestatus'*'up'* ]]

    [[ "$output" != *'manage_engine_nodes.pl'*'bypass'*'action=restore'* ]]
}

@test 'exits nonzero (but still registers engines) if listing ec2 instances fails' {
    run_mce_fail_aws_ec2_describe_instances online

    (( status != 0 ))

    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" == *'manage_cluster.pl'*'addengine'*"${ACTIVE_UNREGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_UNREGISTERED_IP}"* ]]

    [[ "$output" == *'manage_cluster.pl'*'setnodestatus'*'up'* ]]

    [[ "$output" == *'manage_engine_nodes.pl'*'bypass'*'action=restore'* ]]
}

@test 'issues a warning (but exits with zero) if no ec2 instances were listed' {
    run_mce_empty_aws_ec2_describe_instances online

    (( status == 0 ))

	[[ "$output" == *'there are no private IPs for autoscaling instance ID'*'in auto-scaling group'*'(is this the correct auto-scaling group?)'* ]]

    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${ACTIVE_UNREGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_REGISTERED_IP}"* ]]
    [[ "$output" != *'manage_cluster.pl'*'addengine'*"${INACTIVE_UNREGISTERED_IP}"* ]]

    [[ "$output" != *'manage_cluster.pl'*'setnodestatus'*'up'* ]]

    [[ "$output" != *'manage_engine_nodes.pl'*'bypass'*'action=restore'* ]]
}

@test 'does not unregister engines if listing autoscaling groups fails' {
    run_mce_fail_aws_autoscaling_describe_autoscaling_groups offline

    (( status != 0 ))

    [[ "$output" != *deleteengine* ]]
}

@test 'does not unregister engines if listing EC2 instances fails' {
    run_mce_fail_aws_ec2_describe_instances offline

    (( status != 0 ))

    [[ "$output" != *deleteengine* ]]
}

@test 'exits with status 124 if "aws" operations time out' {
    run_mce_aws_take_too_long online

    (( status == 124 ))

    run_mce_aws_take_too_long offline

    (( status == 124 ))
}

@test 'does not exit badly if cluster management actions lag' {
    run_mce_cluster_actions_take_too_long online

    (( status == 0 ))

    run_mce_cluster_actions_take_too_long offline

    (( status == 0 ))
}

@test 'accepts command-line arguments' {
    # 1. For options that take arguments, use the space-separated *and*
    #    equals-sign-separated forms, and
    # 2. Test actions ("offline", "online") mixed in with options, and also
    #    appended to options.
    run_mce \
        --verbose -v \
        --quiet -q \
        --dry-run \
        offline \
		--auto-scaling-group-name foo \
		--auto-scaling-group-name=bar \
		--servergroup 1 \
		--servergroup=2 \
        online \
		--lock-exit-status 3 \
		--lock-exit-status=4 \
		--pidfile-base /this \
		--pidfile-base=/that \
        offline \
        online

    [[ "$output" != *'unrecognized argument'* ]]

}

@test 'requires arguments for certain command-line options' {
    local -a opts=(
		--auto-scaling-group-name
		--servergroup
		--lock-exit-status
		--pidfile-base
    )

    local opt
    for opt in "${opts[@]}"; do
        for form in "$opt" "${opt}="; do
            run_mce "$form"
            (( status == 64 ))
            [[ "$output" == *'missing required argument to "'$opt'" option'* ]]
        done
    done
}

@test 'rejects unknown command-line arguments' {
    run_mce --haha-nope
    (( status == 64 ))
    [[ "$output" == *'unrecognized argument'*'--haha-nope'* ]]
}
