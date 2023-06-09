locals {
    configuration = <<EOL
      {
        "project.id" : "${var.project}",
        "region" : "${var.region}",
        "pubsub.topic" : "${google_pubsub_topic.topic.id}",
        "bt.instance" : "${google_bigtable_instance.instance.name}",
        "bt.contexttable" : "${local.query_context_table_name}",
        "bt.contextcolumnfamily" : "${local.query_context_cf_name}",
        "bt.contextcolumnqualifier" : "exchanges",
        "bt.contenttable" : "${local.content_table_name}",
        "bt.contentcolumnfamily" : "${local.content_cf_name}",
        "bt.contentcolumnqualifier.content" : "content",
        "bt.contentcolumnqualifier.link" : "link",
        "matchingengine.index.id" : "${google_vertex_ai_index.embeddings_index.id}",
        "matchingengine.index.deployment" : "deploy${var.run_name}",
        "matchingengine.indexendpoint.id" : "${data.external.get_indexendpoint_id.result.index_endpoint_id}",
        "matchingengine.indexendpoint.domain" : "${data.external.get_indexendpoint_domain.result.index_endpoint_domain}"
      }
EOL
}

resource "google_secret_manager_secret" "service_config" {
  project   = var.project
  secret_id = "service-configuration-${var.run_name}"

  replication {
    automatic = true
  }

  depends_on = [google_project_service.secret_service]
}

resource "google_secret_manager_secret_version" "service_config_version" {
  secret = google_secret_manager_secret.service_config.id

  secret_data = local.configuration
}

resource "google_cloud_run_v2_service" "services" {
  name     = "${var.run_name}-service"
  location = var.region
  project  = var.project

  template {
    service_account = google_service_account.dataflow_runner_sa.email
    containers {
      image = "gcr.io/${var.project}/${var.region}/${var.run_name}-services:latest"
      startup_probe {
          initial_delay_seconds = 5
          timeout_seconds = 1
          period_seconds = 3
          failure_threshold = 3
          tcp_socket {
            port = 8080
          }
        }
        liveness_probe {
          initial_delay_seconds = 5
          timeout_seconds = 1
          period_seconds = 10
          failure_threshold = 3
          http_get {
            path = "/q/health/live"
          }
        }
        env {
            name = "JAVA_OPTS_APPEND"
            value = "-Dsecretmanager.configuration.version=${google_secret_manager_secret_version.service_config_version.name}"
        }
      resources {
        limits = {
          cpu = "2"
          memory = "2Gi"
        }
      }
    }
  }

  traffic {
    type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent         = 100
  }

  lifecycle {
    ignore_changes = [
      launch_stage,
    ]
  }
}

resource "google_cloud_run_service_iam_member" "google_domain_permission" {
  location = var.region
  project = var.project
  service = google_cloud_run_v2_service.services.name
  role = "roles/run.invoker"
  member = "domain:google.com"
}

resource "google_cloud_run_service_iam_member" "sa_permission" {
  location = var.region
  project = var.project
  service = google_cloud_run_v2_service.services.name
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.dataflow_runner_sa.email}"
}