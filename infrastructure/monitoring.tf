# Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "pixelpipe_dashboard" {
  dashboard_json = jsonencode({
    displayName = "PixelPipe Monitoring Dashboard"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Cloud Function Executions"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=cloudfunctions.googleapis.com/function/execution_count resource.type=cloud_function"
                }
                unitOverride = "1"
              }
            }]
          }
        },
        {
          title = "Cloud Run Request Latency"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type= un.googleapis.com/request_latencies resource.type=cloud_run_revision"
                }
              }
            }]
          }
        }
      ]
    }
  })
}
