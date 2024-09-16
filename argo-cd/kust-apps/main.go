package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"sync"
	"time"
)

func main() {
	start := time.Now()
	file, err := os.ReadFile("argo-cd/kust-apps/kust-apps.json")
	if err != nil {
		log.Fatalln(err)
	}
	var argoApps []gitData
	err = json.Unmarshal(file, &argoApps)
	if err != nil {
		log.Fatalln(err)
	}
	repoToGit := map[string][]gitData{}
	for _, app := range argoApps {
		repoToGit[generateKey(app)] = append(repoToGit[app.RepoURL], app)
	}

	buildReq := make(chan *gitData)
	results := make(chan *gitData)
	go buildKustDirs(buildReq, results)
	go createRequests(repoToGit, buildReq)

	total, errorCount := 0, 0
	for r := range results {
		total++
		if r.Error != nil {
			log.Printf("%v: %v\n", r.Error, r)
			errorCount++
		} else {
			log.Printf("Linted(%d): %s\n", total, r.RepoURL)
		}
	}

	fmt.Printf("Linted %d(%d) kustomize Argo CD applications to kustomize v5.4.3 in %v\n", total, errorCount, time.Since(start))
}

func createRequests(repoToGit map[string][]gitData, buildReq chan *gitData) {
	defer close(buildReq)
	for _, v := range repoToGit {
		for _, app := range v {
			// fmt.Println("adding app")
			buildReq <- &app
		}
	}
}

func generateKey(app gitData) string {
	return fmt.Sprintf("%s/%s/%s", app.RepoURL, app.Path, app.TargetRevision)
}

func buildKustDirs(buildReq <-chan *gitData, results chan<- *gitData) {
	defer close(results)
	/// only allow 100 workers
	wg := &sync.WaitGroup{}
	for w := 0; w < 100; w++ {
		wg.Add(1)
		go buildKustDir(buildReq, results, wg)
	}
	wg.Wait()
}

func buildKustDir(buildReq <-chan *gitData, results chan<- *gitData, wg *sync.WaitGroup) {
	defer wg.Done()
	for r := range buildReq {
		temp, err := os.MkdirTemp("", "kust-*")
		if err != nil {
			r.Error = err
		}
		if err = runCommandWithCancel(temp, "git", "clone", r.RepoURL, "."); err != nil {
			r.Error = err
		}

		if err = runCommandWithCancel(temp, "git", "checkout", r.TargetRevision); err != nil {
			r.Error = err
		}

		if err = runCommandWithCancel(temp, "kustomize", "build", "--enable-helm", r.Path); err != nil {
			r.Error = err
		}
		err = os.RemoveAll(temp)
		if err != nil {
			log.Println(err)
		}
		results <- r
	}
}

func runCommandWithCancel(dir string, binary string, arg ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, binary, arg...)
	errReader, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	out := make(chan []byte)
	go readPipe(out, errReader)
	cmd.Dir = dir
	if err = cmd.Run(); err != nil {
		stderr := string(<-out)
		if stderr != "" {
			err = fmt.Errorf("%s: %v: %s", stderr, err, cmd.String())
		}
		return err
	}
	return nil
}

func readPipe(out chan []byte, rc io.ReadCloser) error {
	defer close(out)
	buf, err := io.ReadAll(rc)
	if err != nil {
		log.Println(err)
		return err
	}
	out <- buf
	return nil
}

type gitData struct {
	RepoURL        string   `json:"repoURL"`
	Path           string   `json:"path"`
	TargetRevision string   `json:"targetRevision"`
	Kustomize      struct{} `json:"kustomize"`
	Error          error
}
