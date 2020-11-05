package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/TheoBrigitte/kimsufi-notify/cmd/check"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:               "kimsufi-notify",
	Short:             "kimsufi availability notifier",
	Long:              `Send notification when kimsufi server are available.`,
	PersistentPreRunE: logLevel,
}

func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.AddCommand(check.Cmd)
}