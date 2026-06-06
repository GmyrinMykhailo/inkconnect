package main

import (
	"log"

	"inkconnect/internal/app"
)

func main() {
	application, err := app.New()
	if err != nil {
		log.Fatalf("bootstrap app: %v", err)
	}
	defer application.Close()

	if err := application.Run(); err != nil {
		log.Fatalf("run app: %v", err)
	}
}
