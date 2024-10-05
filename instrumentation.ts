declare global {
  var secrets: {
    apiKey?: string;
  };
}

export async function register() {
  global.secrets = {};

  let org = process.env.HCP_ORG;
  let project = process.env.HCP_PROJECT;
  let secretName = 'Demo';

  let res = await fetch(
    `https://api.cloud.hashicorp.com/secrets/2023-06-13/organizations/${org}/projects/${project}/apps/${secretName}/open`,
    {
      headers: {
        Authorization: `Bearer ${process.env.HCP_API_TOKEN}`,
      },
    }
  );

  let { secrets } = await res.json();
  global.secrets.apiKey = secrets[0].version.value;

  console.log('Secrets loaded!');
}
