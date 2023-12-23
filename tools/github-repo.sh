#!/bin/bash -e
#
# REFUND HUNTER CONFIDENTIAL
# __________________________
#
#  [2017] - [2023] Refund Hunter
#  All Rights Reserved.
#
# NOTICE: All information contained herein is, and remains the property of Refund Hunter and its
# suppliers, if any.  The intellectual and technical concepts contained herein are proprietary to
# Refund Hunter and its suppliers and may be covered by U.S. and Foreign Patents, patents in
# process, and are protected by trade secret or copyright law. Dissemination of this information or
# reproduction of this material is strictly forbidden unless prior written permission is obtained
# from Refund Hunter.
#

master='main'

usage() {
    echo "Usage: $0 [-c] [-e <ops|dev|tst|prd>] [-k <key-file>] <repo-name>"
    echo "  -c: Create GitHub repo if it does not already exist"
    echo "  -e: Environment name"
    echo "  -k: Key file for decrypting environment repo"
    exit 1
}

while getopts ":ce:k:" opt; do
    case $opt in
        c)
            CREATE_REPO=1
            ;;
        e)
            ENVIRONMENT=$OPTARG
            ;;
        k)
            KEY_FILE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done
shift $((OPTIND-1))
repo_name=$1

# Make sure repo name is specified
if [ -z "${repo_name}" ]; then
    usage
fi

# If key file is specified, make sure it exists
if [ -n "${KEY_FILE}" ]; then
    if [ ! -f "${KEY_FILE}" ]; then
        echo "ERROR: Key file <${KEY_FILE}> does not exist!!!"
        exit 1
    fi
    KEY_FILE=$(realpath "${KEY_FILE}")
fi

# If environment is specified, make sure it is valid
if [ -n "${ENVIRONMENT}" ]; then
    case "${ENVIRONMENT}" in
        ops|dev|tst|prd)
            ;;
        *)
            echo "ERROR: Invalid environment <${ENVIRONMENT}>!!!"
            exit 1
            ;;
    esac
fi

# Make sure GitHub CLI is installed
if ! which gh > /dev/null; then
    echo "ERROR: GitHub CLI is not installed!!!"
    echo "See install instructions at https://cli.github.com/manual/installation"
    exit 1
fi

# Get authenticated GitHub account name
gh_domain="github.com"
gh_account=$(gh auth status -h ${gh_domain} |grep -i "logged in to ${gh_domain}" |awk '{print $7}')
if [ -z "${gh_account}" ]; then
    echo "ERROR: Unable to determine authenticated GitHub account!!!"
    echo "See authentication instructions at https://cli.github.com/manual/gh_auth_login"
    exit 1
fi

create_repo() {
    repo_path=$1
    repo_dir=$2

    # Create GitHub repo if it does not already exist
    git_url=$(gh repo list --json nameWithOwner,sshUrl |jq -r '.[] |select(.nameWithOwner=="'"${gh_account}/${repo_path}"'") |.sshUrl')
    if [ -z "${git_url}" ]; then
        if [ -d "${repo_dir}" ]; then
            echo "ERROR: Directory <${repo_path}> already exists!!!"
            exit 1
        elif [ -z "${CREATE_REPO}" ]; then
            echo "ERROR: GitHub repo <${gh_account}/${repo_path}> does not exist and create flag not specified!!!"
            exit 1
        fi
        gh repo create "${repo_path}" --public --add-readme
        git_url=$(gh repo list --json nameWithOwner,sshUrl |jq -r '.[] |select(.nameWithOwner=="'"${gh_account}/${repo_path}"'") |.sshUrl')
        if [ -z "${git_url}" ]; then
            echo "ERROR: Unable to determine SSH URL for GitHub repo <${gh_account}/${repo_path}>!!!"
            exit 1
        fi
        echo "Created GitHub repo <${gh_account}/${repo_path}>"
    else
        echo "Using existing GitHub repo <${gh_account}/${repo_path}>"
    fi

    # Clone GitHub repo if it does not already exist
    if [ -d "${repo_dir}" ]; then
        # If repo exists, check if it is the same repo
        cd "${repo_dir}"
        remote_url=$(git remote get-url origin)
        if [ "${remote_url}" != "${git_url}" ]; then
            echo "ERROR: Directory <${repo_dir}> already exists and is not the same repo as <${git_url}>!!!"
            exit 1
        fi
    else
        git clone "${git_url}" "${repo_dir}"
        cd "${repo_dir}"
    fi
    git submodule update --init --recursive
}

# Create the source code repo
create_repo "${repo_name}" "${repo_name}"

# If environment is specified, check key file is also specified
if [ -n "${ENVIRONMENT}" ]; then
    if [ -z "${KEY_FILE}" ]; then
        echo "ERROR: Key file must be specified when environment is specified!!!"
        exit 1
    fi
else
    # Exit when environment is not specified
    exit 0
fi

# Check if master branch has unpushed commits
if git merge-base --is-ancestor origin/${master} '@{u}'; then
    echo "ERROR: Source repo <${repo_name}> branch <${master}> has unpushed commits!!!"
    exit 1
fi

# Get current branch name
branch=$(git branch --show-current)

# Stash the current changes in the source repo
if git status --porcelain |grep -q '.'; then
    echo ">>> WARNING: Source repo <${repo_name}>@<${branch}> has uncommitted changes!!!"
    echo ">>> Stashing changes in source repo <${repo_name}> branch <${branch}>..."
    git stash
    stashed=1
fi
git checkout ${master}

# Create the submodules directory if it does not already exist
mkdir -p ".modules"
cd ".modules"

# Create the environment repo for this source repo
create_repo "${repo_name}_${ENVIRONMENT}" "${ENVIRONMENT}"

# Exit if environment repo has uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Environment repo <.modules/${ENVIRONMENT}> has uncommitted changes!!!"
    exit 1
fi

# Decrypt the environment repo using key file
mkdir -p "secret"
if [ ! -f "secret/.gitattributes" ]; then
    echo '* filter=git-crypt diff=git-crypt' > secret/.gitattributes
    echo '.gitattributes !filter !diff' >> secret/.gitattributes
    echo 'Files under this directory are all encrypted in Git.' > secret/README.md
fi
git-crypt unlock "${KEY_FILE}"

# Commit and push changes to environment repo
if git status --porcelain |grep -q '.'; then
    git add .
    git commit -m "Add ${ENVIRONMENT} environment repo for ${repo_name}"
    git push origin
fi

# Check if environment repo is already a submodule
cd ../..
submodule_url=$(git config --file .gitmodules --get "submodule..modules/${ENVIRONMENT}.url" || true)
if [ -z "${submodule_url}" ]; then
    # environment repo is not already a submodule, add it
    git submodule add "${git_url}" ".modules/${ENVIRONMENT}"
    git add .
    git commit -m "Add ${ENVIRONMENT} environment repo as submodule for ${repo_name}"
    git push origin ${master}
fi

# Create branch for environment if it does not already exist
if ! git branch -vv --format '%(upstream)' |grep -q "origin/${ENVIRONMENT}"; then
    # Create branch for environment
    git checkout -b "${ENVIRONMENT}"
    git push -u origin "${ENVIRONMENT}"
fi

# Revert to original branch and un-stash changes
git checkout "${branch}"
if [ -n "${stashed}" ]; then
    git stash pop
fi
