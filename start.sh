#!/bin/bash

/usr/local/bin/tmuxinator start -p tmuxinator.yml

./plot.sh | tee -a ./plotter.log