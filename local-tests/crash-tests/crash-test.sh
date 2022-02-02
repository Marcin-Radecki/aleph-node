# This file is based on run_nodes.sh in repo's root
# need to extract common code of both scripts or use the python wrappers from the same local-tests folder

#!/bin/bash

set -e

function usage(){
  cat << EOF
Usage:
  $0
     --scenario <scenario> which scenario to run: kill or freeze
     [-v|--validators <number>] nunber of validators in authorities. Default: 4
     [-n|--non-validators <number>] number of non-validators in authorities. Default: 0
     where 2 <= --validators <= --validators + --non-validators <= 10
     [-p|--base-path <path>] forwarded as the same --base-path param to aleph-node binary. Default random directory
       in /tmp (echoed to stdout so user'll know).
     [-d|--node-crash-delay] how much seconds to wait before stopping successive nodes and before stop and start_node
      of each node. Default: 30
     [-s|--session-period] session period time in seconds passed to bootstrap-chain. Default: 40
     [-l|--log-file-path] path where aleph-node logs are appended. Default: "."
     [-m|--millisecs-per-block] what's the target time to create new blocks. Default: 2000.
     [-u|--unit-creation-delay] passed to same named param --unit-creation-delay to aleph-node binary, which is an
      internal setting in AlephBFT
     [aleph-node-args] passed as positional arguments to aleph-node binary.
  You can run this script from any folder, but make sure there's aleph-node binary built in target/release/aleph-node
  in root of this repo.
EOF
}

NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)

function get_timestamp() {
  echo "$(date +'%Y-%m-%d %T:%3N')"
}

function error() {
    echo -e "$(get_timestamp) $RED$*$NORMAL"
    usage
    exit 1
}

function info() {
    echo -e "$(get_timestamp) $GREEN$*$NORMAL"
}

function warning() {
    echo -e "$(get_timestamp) $YELLOW$*$NORMAL"
}

function start_node() {
  cmd="$1"
  node_id="$2"
  log_file_path="$3"
  info "Starting node ${node_id}"
  eval "${cmd}" 2>> "${log_file_path}/node-${node_id}.log" > /dev/null &
}

function find_node_pid() {
   pid=$(pgrep -f "aleph-node.*--name node-${node_id}" || error "No such process aleph-node node-${node_id}")
   echo "$pid"
}

function send_signal_to_node() {
   node_id="$1"
   signal="$2"
   pid=$(find_node_pid $node_id)
   info "Sending ${signal} to pid ${pid}"
   kill "-${signal}" $pid
}

function stop_node() {
  node_id="$1"
  info "Stopping node ${node_id}"
  send_signal_to_node $node_id SIGKILL
}

function freeze_node() {
  node_id="$1"
  info "Freezing node ${node_id}"
  send_signal_to_node $node_id SIGSTOP
}

function unfreeze_node() {
  node_id="$1"
  info "Unfreezing node ${node_id}"
  send_signal_to_node $node_id SIGCONT
}

function wait_for() {
  delay="$1"
  info "Sleeping for ${delay}..."
  sleep $delay
}

function sigint_trap()
{
   echo
   info "Cleaning up child process..."
   kill -9 $child_tail_ps_pid
   info "Removing named pipe $aleph_node_tail_log_pipe"
   rm -f "$aleph_node_tail_log_pipe"
   popd > /dev/null
   exit 0
}

function parse_logs_from_aleph_node() {
  grep -B 1 "InvalidAuthoritiesSet\|Error importing block\|Potential long-range attack\|Total peers in aleph network" < "$aleph_node_tail_log_pipe"
}

function perform_kill_node_test() {
  info "Node crash scenario: stop successive nodes every ${NODE_CRASH_DELAY} seconds"


  while true; do
    for i in $(seq 0 "$((nodes_count - 1))"); do
      wait_for $NODE_CRASH_DELAY
      stop_node $i
      wait_for $NODE_CRASH_DELAY
      start_node "${node_start_cmds[$i]}" "$i" "${LOG_FILE_PATH}"
    done
  done
}

function perform_freeze_node_test() {
  info "Node freeze scenario: freeze successive nodes with SIGSTOP/SIGCONT every ${NODE_CRASH_DELAY} seconds"

  while true; do
    for i in $(seq 0 "$((nodes_count - 1))"); do
      wait_for $NODE_CRASH_DELAY
      freeze_node $i
      wait_for $NODE_CRASH_DELAY
      unfreeze_node $i
    done
  done
}

VALIDATORS=4
NON_VALIDATORS=0
BASE_PATH=$(mktemp -d)
LOG_FILE_PATH='.'
NODE_CRASH_DELAY=30
SESSION_PERIOD=40
MILLISECONDS_PER_BLOCK=2000
UNIT_CREATION_DELAY=500

POSITIONAL_ARGS=()

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

while [[ $# -gt 0 ]]; do
  case $1 in
    --scenario)
      SCENARIO="$2"
      shift;shift
      ;;
    -v|--validators)
      VALIDATORS="$2"
      shift;shift
      ;;
    -n|--non-validators)
      NON_VALIDATORS="$2"
      shift;shift
      ;;
    -p|--base-path)
      BASE_PATH="$2"
      shift;shift
      ;;
     -l|--log-file-path)
      LOG_FILE_PATH="$2"
      shift;shift
      ;;
    -d|--node-crash-delay)
      NODE_CRASH_DELAY="$2"
      shift;shift
      ;;
    -s|--session-period)
      SESSION_PERIOD="$2"
      shift;shift
      ;;
    -m|--millisecs-per-block)
      MILLISECONDS_PER_BLOCK="$2"
      shift;shift
      ;;
    -u|--unit-creation-delay)
      UNIT_CREATION_DELAY="$2"
      shift;shift
      ;;
    -*|--*)
      error "Unknown option $1"
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [ -z "${SCENARIO}" ]; then
  error "--scenario not specified!"
elif [ "${SCENARIO}" != "kill" ] && [ "${SCENARIO}" != "freeze" ]; then
  error "parameter --scenario has bad value \"${SCENARIO}\", allowed are: kill or freeze."
fi

info "Stopping aleph-node processes..."
pkill -9 -f aleph-node || info "Found 0 aleph-node processes."

account_ids=(
    "5D34dL5prEUaGNQtPPZ3yN5Y6BnkfXunKXXz6fo7ZJbLwRRH"
    "5GBNeWRhZc2jXu7D55rBimKYDk8PGk8itRYFTPfC8RJLKG5o" \
    "5Dfis6XL8J2P6JHUnUtArnFWndn62SydeP8ee8sG2ky9nfm9" \
    "5F4H97f7nQovyrbiq4ZetaaviNwThSVcFobcA5aGab6167dK" \
    "5DiDShBWa1fQx6gLzpf3SFBhMinCoyvHM1BWjPNsmXS8hkrW" \
    "5EFb84yH9tpcFuiKUcsmdoF7xeeY3ajG1ZLQimxQoFt9HMKR" \
    "5DZLHESsfGrJ5YzT3HuRPXsSNb589xQ4Unubh1mYLodzKdVY" \
    "5GHJzqvG6tXnngCpG7B12qjUvbo5e4e9z8Xjidk3CQZHxTPZ" \
    "5CUnSsgAyLND3bxxnfNhgWXSe9Wn676JzLpGLgyJv858qhoX" \
    "5CVKn7HAZW1Ky4r7Vkgsr7VEW88C2sHgUNDiwHY9Ct2hjU8q")
validator_ids=("${account_ids[@]::VALIDATORS}")
# space separated ids
validator_ids_string="${validator_ids[*]}"
# comma separated ids
validator_ids_string="${validator_ids_string//${IFS:0:1}/,}"

pushd "$SCRIPT_DIR" > /dev/null

info "Bootstrapping chain for validator nodes 0..$((VALIDATORS - 1))"
../../target/release/aleph-node bootstrap-chain --millisecs-per-block ${MILLISECONDS_PER_BLOCK} --session-period ${SESSION_PERIOD} --base-path "$BASE_PATH" \
 --account-ids "$validator_ids_string" --chain-type local > "${BASE_PATH}/chainspec.json" || error "Bootstrapping failed!"

nodes_count=$(( VALIDATORS + NON_VALIDATORS ))
for i in $(seq "$VALIDATORS" "$((nodes_count - 1))"); do
  info "Bootstrapping node $i"
  account_id=${account_ids[$i]}
  ../../target/release/aleph-node bootstrap-node --base-path "$BASE_PATH" --account-id "$account_id" --chain-type local \
   || error "Bootstrapping failed!"
done

declare -a bootnodes
for i in 0 1; do
    pk=$(../../target/release/aleph-node key inspect-node-key --file $BASE_PATH/${account_ids[$i]}/p2p_secret) \
      || echo "Setting bootnodes failed!"
    bootnodes+=("/dns4/localhost/tcp/$((30334+i))/p2p/$pk")
done

info "Running all ${nodes_count} nodes withe below params:"
info "  --node-crash-delay: ${NODE_CRASH_DELAY}"
info "  --session-period: ${SESSION_PERIOD}"
info "  --millisecs-per-block: ${MILLISECONDS_PER_BLOCK}"
info "  --unit-creation-delay: ${UNIT_CREATION_DELAY}"
info "  --base-path is ${BASE_PATH}"
declare -a node_start_cmds
for i in $(seq 0 "$((nodes_count - 1))"); do
  auth="node-$i"
  account_id=${account_ids[$i]}

  info "Purging chain for node ${auth}"
  ../../target/release/aleph-node purge-chain --base-path $BASE_PATH/$account_id --chain $BASE_PATH/chainspec.json -y \
    || echo "purge-chain failed"

  cmd=(
    ../../target/release/aleph-node
    --validator
    --chain "$BASE_PATH/chainspec.json"
    --base-path "$BASE_PATH/$account_id"
    --name "$auth"
    --rpc-port $((9933 + i))
    --ws-port $((9944 + i))
    --port $((30334 + i))
    --bootnodes "${bootnodes[@]}"
    --node-key-file "$BASE_PATH/$account_id/p2p_secret"
    --unit-creation-delay "${UNIT_CREATION_DELAY}"
    --execution Native
    --no-mdns
    -lafa=debug
    "$@")
    node_start_cmds[$i]="${cmd[@]}"
    start_node "${cmd[*]}" "$i" "${LOG_FILE_PATH}"
done


aleph_node_tail_log_pipe=$(mktemp -u)
info "Creating named pipe ${aleph_node_tail_log_pipe}"
mkfifo "$aleph_node_tail_log_pipe"

tail -f -s 0.01 "${LOG_FILE_PATH}/node-"* >"$aleph_node_tail_log_pipe" &
child_tail_ps_pid=$!
parse_logs_from_aleph_node &

trap sigint_trap SIGINT

info "Press Ctrl+C to stop, that kills child aleph-node processes too."
if [ "$SCENARIO" == "freeze" ]; then
  perform_freeze_node_test
elif [ "$SCENARIO" == "kill" ]; then
  perform_kill_node_test
fi
