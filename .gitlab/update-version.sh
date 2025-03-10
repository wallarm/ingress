#!/bin/bash

set -e

PR_BRANCH="update/${COMPONENT_NAME}/${COMPONENT_VERSION}"
GITLAB_REPO_URL="https://${GITLAB_TOKEN_NAME}:${GITLAB_TOKEN}@${GITLAB_HOST}/${GITLAB_REPO}"

git clone ${GITLAB_REPO_URL}
cd packages_versions
git checkout -b ${PR_BRANCH}
git config --local user.name 'project_808_bot'
git config --local user.email 'project808_bot@noreply.${GITLAB_HOST}'
cd packages_versions

FOUND=$(jq -r '.body."'"$COMPONENT_NAME"'" | index("'"$COMPONENT_VERSION"'")' latest.json)
if [ $FOUND != "null" ]; then
    echo "Duplicate: $COMPONENT_VERSION for $COMPONENT_NAME exists already, skipping"
    exit 0
fi

jq '.body."'"$COMPONENT_NAME"'" += ["'"$COMPONENT_VERSION"'"]' latest.json > latest.new.json
VERSIONS=$(jq '.body."'"$COMPONENT_NAME"'" | sort_by( split("[^0-9]+") | map(tonumber? // 0) )' latest.new.json)
jq --argjson versions "$VERSIONS" '.body["'"$COMPONENT_NAME"'"] = $versions' latest.new.json > latest.json
git add latest.json
COMMIT_MESSAGE="Bump ${COMPONENT_NAME} version to ${COMPONENT_VERSION}"
git commit -m "${COMMIT_MESSAGE}"

git push ${GITLAB_REPO_URL} ${PR_BRANCH}

glab auth login --hostname ${GITLAB_HOST} --token ${GITLAB_TOKEN}

echo "Creating merge request ..."
glab mr create \
    --fill \
    --yes \
    --label ${COMPONENT_NAME} \
    --source-branch ${PR_BRANCH} \
    --repo https://${GITLAB_HOST}/${GITLAB_REPO}

echo "Approving merge request ..."
glab mr approve \
    ${PR_BRANCH} \
    --repo https://${GITLAB_HOST}/${GITLAB_REPO}

# Sometimes merging is failed without delay
echo "Sleep ..."
sleep 20

echo "Merging ..."
glab mr merge \
    ${PR_BRANCH} \
    --yes \
    --remove-source-branch \
    --when-pipeline-succeeds=false \
    --repo https://${GITLAB_HOST}/${GITLAB_REPO}

echo "Done."
