import { getInput, info, setFailed } from "@actions/core";
import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { env } from "process";

const setGitUser = (config: any) => {
  info('Initializing Git user...');

  execSync(`git config user.name "${config.username}"`);
  execSync(`git config user.email "${config.email}"`);
};

const createDotNetRcFile = (config: any) => {
  info('Creating .netrc file...');

  const dotNetRcFile = `cat >~/.netrc <<EOF
machine api.heroku.com
    login ${config.email}
    password ${config.api_key}
machine git.heroku.com
    login ${config.email}
    password ${config.api_key}
EOF`;

  execSync(dotNetRcFile);
};

const addEnvironmentVariables = (config: any) => {
  try {
    let envVars: any[] = [];

    if (config.env_file) {
      const env = fs.readFileSync(path.join(config.env_file), "utf8");
      const variables = require('dotenv').parse(env);
      const newVars = [];

      for (let key in variables) {
        newVars.push(key + "=" + variables[key]);
      }

      envVars = [...envVars, ...newVars];
    }

    if (envVars.length !== 0) {
      info('Adding environment variables...');
      execSync(`heroku config:set --app=${config.app_name} ${envVars.join(" ")}`);
    }

    info('No environment variables to add...');
  } catch (error: any) {
    throw error;
  }
};

const addGitRemote = (config: any) => {
  try {
    info('Creating Git remote...');
    execSync('heroku git:remote --app ' + config.app_name);
  } catch (error: any) {
    throw error;
  }
};

const deploy = (config: any) => {
  try {
    execSync(`git push heroku ${config.branch_or_tag}:refs/heads/main`, {
      maxBuffer: 104857600,
    });
  } catch (error: any) {
    throw error;
  }
};

async function run () {
  try {
    const config = {
      api_key: getInput('api_key', {
        required: true,
      }),

      app_name: getInput('app_name', {
        required: true,
      }),

      username: getInput('username', {
        required: true,
      }),

      email: getInput('email', {
        required: true,
      }),

      branch_or_tag: getInput('branch_or_tag', {
        required: true,
      }),

      stack: getInput('stack', {
        required: false,
      }) || env.INPUT_STACK || 'heroku-22',
    }

    setGitUser(config);
    createDotNetRcFile(config);
    addEnvironmentVariables(config);
    addGitRemote(config);
    deploy(config);

  } catch (error: any) {
    setFailed(error.message);
  }
}

run();
