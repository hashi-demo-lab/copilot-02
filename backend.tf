terraform {
  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name = "sandbox_consumer_cloudfrontcopilot-02"
    }
  }
}
