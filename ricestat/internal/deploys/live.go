package deploys

import (
	"context"
	"encoding/json"
	"os/exec"
	"time"

	"github.com/jvS0uzx/hypr-dms-rice/ricestat/internal/snapshot"
)

const liveTimeout = 20 * time.Second

type ghJobs struct {
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"createdAt"`
	Jobs      []struct {
		Name       string    `json:"name"`
		Status     string    `json:"status"`
		Conclusion string    `json:"conclusion"`
		StartedAt  time.Time `json:"startedAt"`
		Steps      []struct {
			Name       string `json:"name"`
			Status     string `json:"status"`
			Conclusion string `json:"conclusion"`
		} `json:"steps"`
	} `json:"jobs"`
}

// fillLive busca jobs e passos do run em andamento. Só é chamada para run que
// não terminou — um `gh run view` por repositório ativo, não por repositório.
func fillLive(ctx context.Context, r *snapshot.DeployRepo) {
	if r.RunID == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, liveTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "gh", "run", "view",
		strconvI(r.RunID),
		"--repo", r.Repo,
		"--json", "status,createdAt,jobs").Output()
	if err != nil {
		return
	}

	var g ghJobs
	if json.Unmarshal(out, &g) != nil {
		return
	}

	if !g.CreatedAt.IsZero() {
		r.ElapsedSec = int(time.Since(g.CreatedAt).Seconds())
	}

	for _, j := range g.Jobs {
		job := snapshot.DeployJob{
			Name:       j.Name,
			State:      jobState(j.Status, j.Conclusion),
			StartedAt:  j.StartedAt,
			StepsTotal: len(j.Steps),
		}
		if !j.StartedAt.IsZero() {
			end := time.Now()
			if j.Status == "completed" {
				end = j.StartedAt // sem completedAt no recorte; elapsed só interessa vivo
			}
			if j.Status != "completed" {
				job.ElapsedSec = int(end.Sub(j.StartedAt).Seconds())
			}
		}
		for _, s := range j.Steps {
			if s.Status == "completed" {
				job.StepsDone++
				continue
			}
			if s.Status == "in_progress" && job.CurrentStep == "" {
				job.CurrentStep = s.Name
			}
		}
		r.StepsTotal += job.StepsTotal
		r.StepsDone += job.StepsDone
		if job.CurrentStep != "" && r.CurrentStep == "" {
			r.CurrentStep = job.CurrentStep
		}
		r.Jobs = append(r.Jobs, job)
	}
}

func jobState(status, conclusion string) string {
	if status != "completed" {
		return snapshot.DeployRunning
	}
	switch conclusion {
	case "success":
		return snapshot.DeploySuccess
	case "cancelled", "skipped":
		return snapshot.DeployUnknown
	default:
		return snapshot.DeployFailure
	}
}

func strconvI(v int64) string {
	const digits = "0123456789"
	if v == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for v > 0 {
		i--
		b[i] = digits[v%10]
		v /= 10
	}
	return string(b[i:])
}
