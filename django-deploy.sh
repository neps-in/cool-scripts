# Credit https://kuttler.eu/code/simple-bash-deployment-script-django/

#!/bin/bash

# Fixed settings
commit=$(git rev-parse HEAD)
date=$(date +%Y%m%d_%H%M%S)
name="${date}_${commit}"
src="~/${name}/git"
venv="~/${name}/virtualenv"
manage="${venv}/bin/python ${src}/src/manage.py"
manage_latest="~/latest/virtualenv/bin/python latest/git/src/manage.py"
archive="${name}.tar.gz"
previous="previous"
latest="latest"

# Dynamic settings
python=/usr/bin/python3.5
pidfile="${previous}/git/src/project.pid"
remote_suggestion="user@example.com"
compilemessages=1

# Arg "parsing"
cmd=$1
remote=${2:-${remote_suggestion}}

if [[ ! "${remote}" ]]; then
  echo "No remote given, aborting, try ${remote_suggestion}"
  exit 1
fi
if [[ ! "${cmd}" ]]; then
  echo No command given, aborting, try deploy remoteclean getdata
  exit 1
fi

if [[ "${cmd}" == "deploy" ]]; then
  set -e
  echo "Transfer archive..."
  git archive --format tar.gz -o "${archive}" "${commit}"
  scp "${archive}" "${remote}:"
  rm -f "${archive}"

  echo "Set up remote host..."
  ssh "${remote}" mkdir -p "${src}"
  ssh "${remote}" tar xzf "${archive}" -C "${src}"
  ssh "${remote}" virtualenv --quiet "${venv}" -p ${python}
  ssh "${remote}" "${venv}/bin/pip" install --quiet --upgrade pip setuptools
  ssh "${remote}" "${venv}/bin/pip" install --quiet -r "${src}/requirements.txt"

  echo "Set up django..."
  ssh "${remote}" "${manage} check"
  ssh "${remote}" "${manage} migrate --noinput"
  if [[ ${compilemessages} -gt 0 ]]; then
    ssh "${remote}" "cd ${src} && ${manage} compilemessages"
  fi
  ssh "${remote}" "${manage} collectstatic --noinput"

  echo "Switching to new install..."
  ssh "${remote}" rm -fv "${previous}"
  ssh "${remote}" mv -v "${latest}" "${previous}"
  ssh "${remote}" ln -s "${name}" "${latest}"

  echo "Killing old worker, pidfile ${pidfile}"
  ssh "${remote}" "test -f ${pidfile} && kill -15 \$(cat ${pidfile}) || echo pidfile not found"

  echo "Cleaning up..."
  ssh "${remote}" rm -f "${archive}"
  rm -f "${archive}"
  set +e
elif [[ "${cmd}" == "getdata" ]]; then
  echo "Dumping prod data"
  ssh "${remote}" "${manage_latest} dumpdata --format json --indent 2 --natural-foreign --natural-primary -o data.json"

  echo "Fetching prod data"
  rsync -avz --progress "${remote}:data.json" data/
fi

if [[ "${cmd}" == "deploy" || "${cmd}" == "remoteclean" ]]; then
  echo "Deleting obsolete deploys"
  ssh "${remote}" '/usr/bin/find . -maxdepth 1 -type d -name "2*" | ' \
    'grep -v "$(basename "$(readlink latest)")" | ' \
    'grep -v "$(basename "$(readlink previous)")" | ' \
    '/usr/bin/xargs /bin/rm -rf'
  ssh "${remote}" rm -fv 2*tar.gz
fi