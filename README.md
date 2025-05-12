# thin

Thin is a github webhook server that is extremely thin. It's a single main file that receives webhook requests
and starts a command you specify to do any CI/CD, piping the payload into STDIN. It has no Go dependencies beyond the standard library

The only real lifting it will do is verify the signature from github given a secret. Beyond that, it leaves everything
else up to you

## Running

```shell
Usage of thin:
  -cmd string
        Command to run when webhook has been received
  -log.fmt string
        Format to use, json or logfmt/text (default "logfmt")
  -log.lvl string
        Log level to use (default "info")
  -log.src
        Show the line in source code where the log is
  -port uint
        port to use
  -secret string
        Secret to use. Set this flag, or use env var $SECRET
```

## Deploying

Deploying it via nginx is also supported in the repo. Deploying it is useful via ssh:

```shell
cat deploy-selfsigned.sh | ssh <SERVER>
```