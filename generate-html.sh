#!/usr/bin/env bash

export COLUMNS=180
export ROWS=10000

function faketty() {
  script -qefc "bash -c 'stty cols $COLUMNS; stty rows $ROWS; $@'"
}

function htmltemplate() {
cat <<- EOF
<!DOCTYPE html><html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><title>Tasks</title><style>body{color:white;background-color:black;text-align:center;}a{color:white;}</style></head><body><pre>
EOF
cat -
cat <<- EOF
</pre></body></html>
EOF
}

mkdir -p .tmp
trap 'rm -rf ".tmp"' EXIT
mkdir -p public/files/all

IFS=$'\n'
for f in $(echo "template resolved recurring pending paused delegated deferred active" | tr ' ' '\n'); do
  if [ -d "$f" ]; then
    cp -r "$f" public/files
    find "$f" -type f -exec cp "{}" public/files/all \;
  fi
done

( cd ".tmp";
htmltemplate > "../public/index.html" <<- EOF
<a href="resolved/index.html">resolved</a> | <a href="templates/index.html">templates</a> | <a href="files/recurring/">recurring</a> | <a href="files/pending/">pending</a> | <a href="paused/index.html">paused</a> | <a href="files/delegated/">delegated</a> | <a href="files/deferred/">deferred</a> | <a href="active/index.html">active</a> | <a href="unorganised/index.html">unorganised</a> | <a href="files/all/">all</a>

$(faketty 'dstask next' | aha -n)

<a href="projects/index.html">projects</a> | <a href="tags/index.html">tags</a>
EOF

mkdir -p ../public/projects/
htmltemplate > "../public/projects/index.html" <<- EOF
<a href="../index.html">home</a>

$(faketty 'dstask show-projects' | aha -n)
EOF

mkdir -p ../public/tags/
htmltemplate > "../public/tags/index.html" <<- EOF
<a href="../index.html">home</a>

$(faketty 'dstask show-tags' | aha -n)
EOF

mkdir -p ../public/unorganised/
htmltemplate > "../public/unorganised/index.html" <<- EOF
<a href="../index.html">home</a>

$(faketty 'dstask show-unorganised' | aha -n)
EOF

mkdir -p ../public/templates/
htmltemplate > "../public/templates/index.html" <<- EOF
<a href="../index.html">home</a> | <a href="../files/template/">raw</a>

$(faketty 'dstask show-templates' | aha -n)
EOF

mkdir -p ../public/resolved/
htmltemplate > "../public/resolved/index.html" <<- EOF
<a href="../index.html">home</a> | <a href="../files/resolved/">raw</a>

$(faketty 'dstask show-resolved' | aha -n)
EOF

mkdir -p ../public/paused/
htmltemplate > "../public/paused/index.html" <<- EOF
<a href="../index.html">home</a> | <a href="../files/paused/">raw</a>

$(faketty 'dstask show-paused' | aha -n)
EOF

mkdir -p ../public/active/
htmltemplate > "../public/active/index.html" <<- EOF
<a href="../index.html">home</a> | <a href="../files/active/">raw</a>

$(faketty 'dstask show-active' | aha -n)
EOF
)

