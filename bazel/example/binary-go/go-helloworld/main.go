package main

import (
	"fmt"

	"github.com/rumstead/dev-notes/bazel/example/binary-go/go-hello-module/greetings"
)

func main() {
	fmt.Println(greetings.Hello("rumstead"))
}
