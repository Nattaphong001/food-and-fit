package main

import (
	"fmt"
	"food_and_fit_api/utils"

	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load(".env")
	tok, err := utils.GenerateToken(1)
	if err != nil {
		panic(err)
	}
	fmt.Println(tok)
}
