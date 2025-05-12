package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

type app struct {
	*slog.Logger
	port        uint16
	secret, cmd string
}

func newApp() (*app, error) {
	logLvl := flag.String("log.lvl", "info", "Log level to use")
	logSrc := flag.Bool("log.src", false, "Show the line in source code where the log is")
	logFmt := flag.String("log.fmt", "logfmt", "Format to use, json or logfmt/text")

	secret := flag.String("secret", "", "Secret to use. Set this flag, or use env var $SECRET")

	command := flag.String("cmd", "", "Command to run when webhook has been received")

	port := flag.Uint("port", 0, "port to use")

	flag.Parse()

	l, err := logger(*logSrc, *logLvl, *logFmt)
	if err != nil {
		return nil, err
	}

	if *secret == "" {
		if *secret = os.Getenv("SECRET"); *secret == "" {
			l.Error("missing secret")
			return nil, fmt.Errorf("missing secret")
		}
	}

	if *command == "" {
		l.Error("missing command")
		return nil, fmt.Errorf("missing command")
	}

	p := *port
	return &app{Logger: l, secret: *secret, port: uint16(p), cmd: *command}, nil
}

func logger(logSrc bool, logLvl, logFmt string) (*slog.Logger, error) {
	opts := slog.HandlerOptions{AddSource: logSrc}

	switch strings.ToLower(logLvl) {
	case "debug":
		opts.Level = slog.LevelDebug
	case "info":
		opts.Level = slog.LevelInfo
	case "warn":
		opts.Level = slog.LevelWarn
	case "error", "err":
		opts.Level = slog.LevelError
	default:
		return nil, fmt.Errorf("invalid lvl %s", logLvl)
	}

	var h slog.Handler
	switch strings.ToLower(logFmt) {
	case "logfmt", "text":
		h = slog.NewTextHandler(os.Stdout, &opts)
	case "json":
		h = slog.NewJSONHandler(os.Stdout, &opts)
	default:
		return nil, fmt.Errorf("invalid fmt %s", logFmt)
	}

	return slog.New(h), nil
}

func kill(err error) {
	fmt.Println(err)
	os.Exit(1)
}

func main() {
	a, err := newApp()
	if err != nil {
		kill(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		buf, err := io.ReadAll(r.Body)
		if err != nil {
			a.Error("failed reading request body")
			return
		}
		defer r.Body.Close()

		if len(a.secret) > 0 {
			signature := r.Header.Get("X-Hub-Signature-256")
			if len(signature) == 0 {
				a.Error("webhook received with invalid signature header", "got", signature)
				return
			}

			signature = strings.TrimPrefix(signature, "sha256=")

			mac := hmac.New(sha256.New, []byte(a.secret))
			if _, err = mac.Write(buf); err != nil {
				a.Error("failed writing MAC", "err", err)
				return
			}

			want := hex.EncodeToString(mac.Sum(nil))
			if !hmac.Equal([]byte(signature), []byte(want)) {
				a.Error("mac verification failed", "got", want, "header", signature)
				return
			}
		}

		c := exec.Command(a.cmd)
		c.Stdin = bytes.NewReader(buf)
		if err = c.Run(); err != nil {
			a.Error("command errored", "err", err)
			return
		}

		a.Info("successful CI run")
	})

	http.ListenAndServe(fmt.Sprintf(":%d", a.port), nil)
}
