#!/bin/bash

set -e
source ./yaml.sh
create_variables config.yaml

array::join() {
  (($#)) || return 1
  local -- delim="$1" str IFS=
  shift
  str="${*/#/$delim}"
  echo "${str:${#delim}}"
}

get_previous_store() {
  grep -E -om1 $(array::join "|" ${destinations[@]}) "$log_path/$1"
}

get_next_store() {
  for i in "${!destinations[@]}"; do
    # if the previous store was the last store in the config.yaml, make the next store the first destination from config
    if [[ "$1" == ${destinations[$((${#destinations[@]}-1))]} ]]; then
      echo ${destinations[0]}
      break
    elif [[ "$1" == ${destinations[$i]} ]]; then
      echo ${destinations[$(($i+1))]}
      break
    fi
  done
}

get_log_name() {
  echo "$(printf "%02g" $(($1+1)))_$(printf "%02g" $2)_$(date +%Y-%m-%d_%H-%M-%S).log"
}

start_plotting() {
  tmux new -d -s "cycle_$1_plot_$2"
  tmux send-keys -t "cycle_$1_plot_$2" \
    "cd $chia_path; . ./activate; chia plots create -k $chia_conf_k $([[ $chia_conf_override_k == "true" ]] && printf "%s\n" "--override-k") $([[ $chia_conf_e == "true" ]] && printf "%s\n" "-e") -u $chia_conf_u -b $chia_conf_b -r $chia_conf_r -f $chia_conf_f -p $chia_conf_p -t $temp_path -2 $3 -d $3 | tee $log_path/$4" ENTER
  sleep 15m
}

prev_cycle_n_process_done() {
  grep -Eo "Renamed final file" $log_path/$(printf "%02g" $1)_$(printf "%02g" $2)*.log 2>/dev/null | wc -l
}

# get available space on each destination
for i in "${!destinations[@]}"; do
  store_space+=($(($(stat -f --format="%a*%S" ${destinations[$i]}))),${destinations[$i]})
done

# sort destination space in descending order
IFS=$'\n' sorted_store_space=($(sort -nr <<<"${store_space[*]}"))
unset IFS

count=0
while [ $count -lt $cycles_count ]; do
  if [ $(ls $log_path/*.log 2>/dev/null | wc -l) -eq 0 ] && [ $count = 0 ]; then
    echo "$(date +%Y-%m-%d_%H-%M-%S) starting cycle 1"
    for (( process=1; process <= $processes; process++ )); do
      last_log=$(ls -t -Icompleted $log_path | sort -r | head -n1)

      if ! [[ -n $last_log ]]; then
        # when no log to read the previous store, set it to the store with the most space
        next_store=$(sed -e 's#.*,\(\)#\1#' <<< "${sorted_store_space[0]}")
      else
        previous_store=$(get_previous_store ${last_log}) || true
        next_store=$(get_next_store ${previous_store})
      fi

      echo "starting process $process"

      log=$(get_log_name $count $process)

      start_plotting $(($count+1)) $process $next_store $log

      # immediately attach to the first cycle's processes to the tmux split view
      tmux send-keys -t "plot_${process}" "TMUX='' tmux a -t cycle_$(($count+1))_plot_${process}" ENTER

      sleep 30
    done
    count=$(($count+1))
  elif [ $count = 0 ]; then
    # when the script first runs, move old logs to completed directory
    mv $log_path/*.log $log_path/completed/
  fi

  # check for when the first process from the previous cycle finishes
  first_process_prev_cycle_finished=$(grep -Eo "Renamed final file" $log_path/$(printf "%02g" $count)_01*.log 2>/dev/null | wc -l)
  if [ $first_process_prev_cycle_finished -eq 1 ]; then
    echo "$(date +%Y-%m-%d_%H-%M-%S) starting cycle $(($count+1))"
    for (( process=1; process <= $processes; process++ )); do
      # wait for $process from previous cycle to finish
      while [ $(prev_cycle_n_process_done $count $process) -eq 0 ]; do
        sleep 5
      done

      last_log=$(ls -t -Icompleted $log_path | sort -r | head -n1)

      previous_store=$(get_previous_store ${last_log}) || true
      next_store=$(get_next_store ${previous_store})

      echo "starting process $process"

      log=$(get_log_name $count $process)

      start_plotting $(($count+1)) $process $next_store $log

      sleep 30
    done

    # kill previous cycle windows and attach new cycle windows to long running plot_x windows
    sleep 10
    for (( process=1; process <= $processes; process++ )); do
      tmux kill-window -t "cycle_${count}_plot_${process}"
      sleep 5
      tmux send-keys -t "plot_${process}" "TMUX='' tmux a -t cycle_$(($count+1))_plot_${process}" ENTER
      sleep 5
    done

    count=$(($count+1))
  fi
  sleep 1
done
