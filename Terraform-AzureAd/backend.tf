// TODO: Add your organization name and workspace name for your own backend or remove this block if you are using a different backend or running locally
terraform {
  backend "remote" {
    organization = "elven" # org name
    workspaces {
      name = "nic-rebel-2025" # name for app's state
    }
  }
}