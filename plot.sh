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

count=0
while [ $count -lt $cycles_count ]; do
  last_log=$(ls -t $log_path | sort -r | head -n1)
  # if there's no logs, start from the beginning
  if ! [[ -n $last_log ]]; then
    echo $(date +%Y-%m-%d_%H-%M-%S) "starting new cycle"
    next_store=${destinations[0]}
    for (( p=1; p <= $processes; p++ )); do
      # check if logs exist now
      last_log=$(ls -t $log_path | sort -r | head -n1)
      if [ -f "$log_path/$last_log" ]; then
        # get the last store destination used
        previous_store=$(grep -E -om1 $(array::join "|" ${destinations[@]}) "$log_path/$last_log") || true
        for i in "${!destinations[@]}"; do
          # if the previous store was the last store in the config.yaml, make the next store the first destination from config
          if [[ "$previous_store" == ${destinations[$((${#destinations[@]}-1))]} ]]; then
            next_store=${destinations[0]}
          elif [[ "$previous_store" == ${destinations[$i]} ]]; then
            next_store=${destinations[$(($i+1))]}
          fi
        done      
      fi
      log_name=$(printf "%06g" $p)
      echo $(date +%Y-%m-%d_%H-%M-%S) "plotting $log_name"
      echo "Starting plotting progress into temporary dirs: /plots/temp and $next_store" | tee -a $log_path/$log_name.log
      screen -dmS plot$i -L -Logfile $log_path/$log_name.log bash \
        -c "cd $chia_path; . ./activate; chia plots create -k $chia_conf_k $([[ $chia_conf_e == "true" ]] && printf "%s\n" "-e") -u $chia_conf_u -b $chia_conf_b -r $chia_conf_r -t $temp_path -2 $next_store -d $next_store"
      sleep 2
    done
    count=$(($count+1))
  fi

  # when the latest log has hit phase 3, start a new cycle
  if [ -f "$log_path/$last_log" ] && grep -Fxq "Starting phase 3/4" "$log_path/$last_log"; then
    echo $(date +%Y-%m-%d_%H-%M-%S) "starting new cycle"
    for (( p=1; p <= $processes; p++ )); do
      last_log=$(ls -t $log_path | sort -r | head -n1)
      last_log_increment=$(echo "${last_log}" | sed -e 's:^0*::' | cut -f 1 -d '.')
      new_log_increment=$(($last_log_increment+1))
      log_name=$(printf "%06g" $new_log_increment)
      previous_store=$(grep -E -om1 $(array::join "|" ${destinations[@]}) "$log_path/$last_log") || true
      for i in "${!destinations[@]}"; do
        # if the previous store was the last store in the config.yaml, make the next store the first destination from config
        if [[ "$previous_store" == ${destinations[$((${#destinations[@]}-1))]} ]]; then
          next_store=${destinations[0]}
        elif [[ "$previous_store" == ${destinations[$i]} ]]; then
          next_store=${destinations[$(($i+1))]}
        fi
      done 
      echo $(date +%Y-%m-%d_%H-%M-%S) "plotting $log_name"
      screen -dmS plot$i -L -Logfile $log_path/$log_name.log bash \
        -c "cd $chia_path; . ./activate; chia plots create -k $chia_conf_k $([[ $chia_conf_e == "true" ]] && printf "%s\n" "-e") -u $chia_conf_u -b $chia_conf_b -r $chia_conf_r -t $temp_path -2 $next_store -d $next_store"
      sleep 2
    done
    count=$(($count+1))
  fi

  echo "sleeping for 5 seconds"
  sleep 5
done