# Pact Web

Web IDE for the [Pact](https://pact-language.readthedocs.io/en/latest/) language, including support for deployments to backends (blockchains, test servers).

# Hacking

This is an [Obelisk project](https://github.com/obsidiansystems/obelisk), so find general hacking instructions there.

Since release 1.4 pact-web has support GitHub gist sharing so it needs client credentials for operation. See section `Deployments` for details on howto obtain them and put the client id and the client secret in the appropriate config files.

The homepage URL will be http://localhost:8000, the authorization callback url will be http://localhost:8000/oauth/redirect/github .

# Deployments

## Clone the repo

```bash
$ git clone git@github.com:kadena-io/pact-web.git
$ cd pact-web
```
Make sure you have checked out the master branch.

## Deploy

### Initialise `ob deploy` as usual:

```bash
$ ob deploy init <deploydir> --ssh-key <key> --hostname <hostname> --route <URI> --admin-email <email>
```

And change to the just created deployment repo:

```bash
$ cd <deploydir>
```

Where `deploydir` is the same as above.

### Setting up production mode and the network list

In the `deploydir` directory, create a file at `config/common/networks`, it must contain a list of networks. With each network consisting of at least one host. A network can either be some chainweb deployment or also some pact -s server. pact-web will auto detect what it actually is:

```
    testnet: us1.chainweb.com us2.chainweb.com eu1.chainweb.com eu2.chainweb.com ap1.chainweb.com ap2.chainweb.com
    pact: pact01.kadena.io pact02.kadena.io
```

This file must exist, so pact-web won't start up in development mode (launching its own pact servers), as of this writing it should also be populated with entries.

The first entry in the file will be chosen as the current network, unless the user picked a different one. The user will also be able to modify networks at runtime. The above configuration will be the default and the one that gets applied, when the user presses "Restore Defaults".

### Provide remote verification server

pact-web supports verification of Pact modules, unfortunately the prover used is z3 which is implemented in C++ and is therefore not available on ghcjs. To make it still work, we use a remote verification server for verifying contracts. Please provide a file `config/common/verification-server` containing the base url of some `pact -s` server, e.g.:

```
https://pact01.kadena.io

```

### OAuth GitHub configuration

pact-web needs GitHub client credentials for the Gist sharing feature. So before deployment, you need to provide those credentials via obelisk executable configs.

To create a GitHub OAuth application, login into GitHub, then go to `Settings` of either your GitHub account or of an organization that should host the application. There you can find `Developer Settings` allowing you to create an OAuth application.

Direct links:

- Create a personal oAuth application, belonging to your account [here](https://github.com/settings/developers)
- Create an OAuth application belonging to an organization here: https://github.com/organizations/YOUR-ORGANIZATION/settings/applications

Replace `YOUR-ORGANIZATION` with your organization's name.

Press `Register an application` or `New application`, then give it a name of your liking and fill out the url, which should match the url where pact-web will be running. For the Authorization callback URL use the following:

https://HOST-WHERE-PACT-WEB-RUNS/oauth/redirect/github


Replace `HOST-WHERE-PACT-WEB-RUNS` with your actual host name and press `Register application`.

You will be presented with a screen showing your application's client id and its client secret.

The client id must go into `config/common/oauth/github/client-id`. The client secret must go into `config/backend/oauth/github/client-secret` of your deployment directory (or in your checked out source repository, when setting up a developer environment).

## Google Analytics tracking

pact-web is set up for basic Google Analytics tracking. You can configure the used tracking id by providing a config file in the deploy directory containing your desired tracking id:

```bash
$ cd <dirname>
$ mkdir config/frontend
$ echo 'your-new-id' > config/frontend/tracking-id
```

Then of course, run the deployment:

```bash
ob deploy push
```

### Actual deployment

Use `ob deploy` from the deploy directory:

```bash
$ ob deploy update
$ ob deploy push
```

# Deploy pact -s server instances

This repo also includes support for setting up test server backends for
simulating a blockchain. To deploy such a test server do the following:

Change to the pact-server directory:

```bash
$ cd pact-server
```

Run the deploy script:

```bash
$ ./deploy.sh <ssh-key> <hostname> <admin-email>
```

It will deploy a pact -s server to the given hostname using the given ssh-key.
An nginx instance will be setup as a reverse proxy to the pact -s server,
serving its API via https.
