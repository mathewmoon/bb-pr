#!/bin/bash

function usage(){
cat<<EOF

Create a PR in Bitbucket.org and return a link for the PR.

Usage:
  -D|--description          PR Description
  -d|--destination          Destination branch
  -s|--source               Source branch
  -t|--title                PR title
  -u|--user                 BB username
  -p|--password             BB password
  -r|--reviewrs             Comma delimited list of reviewer usernames
  -c|--close-source-branch  Close the source branch on merge (Takes no arguments)
  -o|--print-full-output    Print the full output returned by the API (Takes no arguments)
EOF
}

CLOSE_BRANCH=false

while [[ ! -z $1 ]]; do
  case $1 in
    -c|--close-source-branch)
      CLOSE_BRANCH=true
      ;;
    -u|--user)
      shift
      USERNAME="$1"
      ;;
    -p|--password)
      shift
      PASSWORD="$1"
      ;;
    -D|--description)
      shift
      DESCRIPTION="$1"
      ;;
    -t|--title)
      shift
      TITLE="$1"
      ;;
    -d|--destination)
      shift
      DESTINATION="$1"
      ;;
    -s|--source)
      shift
      SOURCE="$1"
      ;;
    -r|--reviewers)
      shift
      REVIEWLIST="$1"
      ;;
    -o|--print-full-output)
      PRINT_FULL_OUTPUT=true
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [ -z "$USERNAME" ]; then
  if [ ! -z "${BB_USERNAME}" ]; then
    USERNAME=${BB_USERNAME}
  else
    echo -n "bitbucket username:"
    read USERNAME
  fi
fi

if [ -z "$PASSWORD" ]; then
  if [ ! -z "${BB_PASSWORD}" ]; then
    PASSWORD=${BB_PASSWORD}
  else
    echo -n "bitbucket password:"
    read PASSWORD
  fi
fi


REMOTE=$(git remote show origin |grep Fetch|sed -r 's#^.*:##g')
USER=$(echo $REMOTE | cut -d '/' -f1)
SLUG=$(echo $REMOTE | cut -d '/' -f2 | cut -d '.' -f1)
CURRENT_BRANCH=$(git branch|grep '*'|awk '{print $2}')

[ -z "$SOURCE" ] && SOURCE=$CURRENT_BRANCH
[ -z "$DESTINATION" ] && echo 'destination branch:' && read DESTINATION
[ -z "$TITLE" ] && echo -n 'title:' && read TITLE
[ -s "$DESCRIPTION" ] && DESCRIPTION="Merge ${SOURCE} with ${DESTINATION}"

if [ ! -z "${REVIEWLIST}" ]; then
  for user in $(echo $REVIEWLIST | sed 's/\s//g' | sed 's/,/ /g'); do
    UUID=$(curl -s https://api.bitbucket.org/2.0/users/${user} | egrep -o '"uuid": "{(([0-9a-z]+\-?)+)}"')
    REVIEWERS=$(cat<<EOF
      ${REVIEWERS},
      {
        $UUID
      }
EOF
  )
  done
  REVIEWERS=$(egrep -v '^\s*,\s*$'<<<${REVIEWERS})
else
  REVIEWERS=""
fi

JSON=$(cat<<EOF
{
    "title": "${TITLE}",
    "description": "${DESCRIPTION}",
    "reviewers": [
      ${REVIEWERS}
    ],
    "close_source_branch": "${CLOSE_BRANCH}",
    "source": {
        "branch": {
            "name": "${SOURCE}"
        }
    },
    "destination": {
        "branch": {
            "name": "${DESTINATION}"
        }
    }
}
EOF
)

url="https://bitbucket.org/api/2.0/repositories/${USER}/${SLUG}/pullrequests"

RESULT=$(curl -s "https://bitbucket.org/api/2.0/repositories/${USER}/${SLUG}/pullrequests" \
  -X POST \
  -H 'Content-Type:application/json' \
  --user "${USERNAME}:${PASSWORD}" \
  --data "${JSON}"
)

if echo "${RESULT}" | grep -q '{"type": "error"' || [ "${PRINT_FULL_OUTPUT}" = "true" ]; then
  echo "${RESULT}"
else
  if ! echo "${RESULT}" | grep -q '{"type": "error"'; then
    echo "You can review your PR at $(echo "${RESULT}" | sed 's/\}/\n/g' | egrep -o 'html": {"href": "https://bitbucket.org/.*/[0-9]+' | grep pull-requests | sed 's/.*\s//g' | tr -d '"')"
  fi
fi
