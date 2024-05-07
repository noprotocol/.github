import { debug, getInput, setFailed, setOutput } from "@actions/core";
import { getOctokit, context } from "@actions/github";

import { env } from "process";

async function run () {
  try {
    const owner = context.repo.owner;
    const repo = context.repo.repo;
    const token = getInput('token', {
      required: true,
    });

    const tagName = getInput('tag_name', {
      required: true,
    });

    const branch = getInput('branch', {
      required: false,
    }) || env.INPUT_BRANCH || 'main'

    if (! token) {
      setFailed('Input "token" is required');
    }

    if (! tagName) {
      setFailed('Input "tag_name" is required');
    }

    const github = getOctokit(token);

    const response = await github.request(
      'POST /repos/{owner}/{repo}/releases/generate-notes',
      {
        owner,
        repo,
        tag_name: tagName,
        target_commitish: branch,
      },
    );

    const releaseNotes = response.data.body;

    debug(`Release notes: ${releaseNotes}`);

    setOutput('release_notes', releaseNotes);
  } catch (error: any) {
    setFailed(error.message);
  }
}

run();
