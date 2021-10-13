#!/usr/bin/env bash

export COLUMNS=180

function faketty() {
  script -qefc "bash -c 'stty cols $COLUMNS; $@'"
}

mkdir -p .tmp
trap 'rm -rf ".tmp"' EXIT
mkdir -p public/

( cd ".tmp";

cat > "../public/index.html" <<- EOF
<!DOCTYPE html><html><head><title>Tasks</title></head><body style="color:white; background-color:black; text-align:center">
<pre>
$(faketty 'dstask next' | aha -n)

View completed tasks <a href="resolved/">here</a>.
</pre></body></html>
EOF
)

IFS=$'\n'
for f in $(echo "template resolved recurring pending paused delegated deferred active" | tr ' ' '\n'); do
  [ -d "$f" ] && cp -r "$f" public/ || :
done
