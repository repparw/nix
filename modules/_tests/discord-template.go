package main

import (
	"bytes"
	"fmt"
	"os"
	"text/template"
)

type alert struct {
	Status      string
	Labels      map[string]string
	Annotations map[string]string
}

type alerts []alert

func (all alerts) Firing() alerts {
	return all.withStatus("firing")
}

func (all alerts) Resolved() alerts {
	return all.withStatus("resolved")
}

func (all alerts) withStatus(status string) alerts {
	var selected alerts
	for _, a := range all {
		if a.Status == status {
			selected = append(selected, a)
		}
	}
	return selected
}

type data struct {
	Status            string
	CommonLabels      map[string]string
	CommonAnnotations map[string]string
	Alerts            alerts
}

func main() {
	text, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	tmpl := template.Must(template.New("notifications").Parse(string(text)))
	critical := alert{Status: "firing", Labels: map[string]string{"severity": "critical"}}
	warning := alert{Status: "firing", Labels: map[string]string{"severity": "warning"}}
	recovered := alert{Status: "resolved", Labels: map[string]string{"severity": "critical"}}
	cases := []struct {
		name, status, alertname, expected string
		alerts                            alerts
	}{
		{"mixed severities", "firing", "", "Critical · alpha", alerts{warning, critical}},
		{"critical first", "firing", "", "Critical · alpha", alerts{critical, warning}},
		{"resolved critical with firing warning", "firing", "", "Warning · alpha", alerts{warning, recovered}},
		{"warning", "firing", "Disk space warning", "Disk warning · alpha", alerts{warning}},
		{"critical", "firing", "Disk space critical", "Disk critical · alpha", alerts{critical}},
		{"recovery", "resolved", "", "Resolved · alpha", alerts{recovered}},
		{"datasource failure", "firing", "DatasourceError", "Monitoring unavailable · alpha", alerts{warning}},
	}
	for _, tc := range cases {
		var output bytes.Buffer
		payload := data{Status: tc.status, CommonLabels: map[string]string{"host": "alpha", "alertname": tc.alertname}, Alerts: tc.alerts}
		if err := tmpl.ExecuteTemplate(&output, "fleet.discord.title", payload); err != nil {
			panic(err)
		}
		if output.String() != tc.expected {
			panic(fmt.Sprintf("%s: got %q, want %q", tc.name, output.String(), tc.expected))
		}
	}
}
