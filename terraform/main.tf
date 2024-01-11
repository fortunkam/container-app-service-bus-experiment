locals {
  resource_group_name                             = "rg-${var.resource_suffix}"
  vnet_name                                       = "vnet-${var.resource_suffix}"
  core_address_space                              = "10.0.0.0/22"
  container_app_environment_subnet_address_prefix = "10.0.0.0/26"
  container_app_environment_name                  = "cae-${var.resource_suffix}"
  workload_profile_name                           = "wp-${var.resource_suffix}"
  managed_identity_id                             = "mid-${var.resource_suffix}"
  service_bus_namespace_name                      = "sb-${var.resource_suffix}"
  log_analytics_name                              = "log-${var.resource_suffix}"
  app_insights_name                               = "appi-${var.resource_suffix}"
}

resource "azurerm_resource_group" "core" {
  location = var.location
  name     = local.resource_group_name
}

resource "azurerm_virtual_network" "core" {
  name                = local.vnet_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  address_space       = [local.core_address_space]
}

resource "azurerm_subnet" "container_app_environment" {
  name                 = "ContainerAppEnvironmentSubnet"
  virtual_network_name = azurerm_virtual_network.core.name
  resource_group_name  = azurerm_resource_group.core.name
  address_prefixes     = [local.container_app_environment_subnet_address_prefix]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  service_endpoints = ["Microsoft.ServiceBus"]
}

resource "azurerm_network_security_group" "default_rules" {
  name                = "nsg-default-rules"
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
}

resource "azurerm_subnet_network_security_group_association" "container_app_environment" {
  subnet_id                 = azurerm_subnet.container_app_environment.id
  network_security_group_id = azurerm_network_security_group.default_rules.id
}

resource "azurerm_user_assigned_identity" "cae_id" {
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  name                = local.managed_identity_id
}

data "azurerm_container_registry" "mgmt_acr" {
  name                = var.acr_name
  resource_group_name = var.mgmt_resource_group_name
}

resource "azurerm_role_assignment" "acrpull_role" {
  scope                = data.azurerm_container_registry.mgmt_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.cae_id.principal_id
}

resource "azurerm_servicebus_namespace" "sb" {
  name                = local.service_bus_namespace_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  sku                 = "Premium"
  capacity            = "1"
}

resource "azurerm_servicebus_queue" "test_incoming" {
  name         = "relay-incoming"
  namespace_id = azurerm_servicebus_namespace.sb.id

  enable_partitioning = false
}

resource "azurerm_servicebus_queue" "test_outgoing" {
  name         = "relay-outgoing"
  namespace_id = azurerm_servicebus_namespace.sb.id

  enable_partitioning = false
}

resource "azurerm_servicebus_namespace_network_rule_set" "servicebus_network_rule_set" {
  namespace_id                  = azurerm_servicebus_namespace.sb.id
  default_action                = "Deny"
  public_network_access_enabled = true
  network_rules {
    subnet_id                            = azurerm_subnet.container_app_environment.id
    ignore_missing_vnet_service_endpoint = false
  }
}

resource "azurerm_role_assignment" "servicebus_sender" {
  scope                = azurerm_servicebus_namespace.sb.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.cae_id.principal_id
}

resource "azurerm_role_assignment" "servicebus_receiver" {
  scope                = azurerm_servicebus_namespace.sb.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.cae_id.principal_id
}

resource "azurerm_log_analytics_workspace" "core" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  retention_in_days   = 30
  sku                 = "PerGB2018"
}

resource "azurerm_application_insights" "core" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  workspace_id        = azurerm_log_analytics_workspace.core.id
  application_type    = "web"
}

resource "azurerm_container_app_environment" "container_app_environment" {
  name                                        = local.container_app_environment_name
  location                                    = azurerm_resource_group.core.location
  resource_group_name                         = azurerm_resource_group.core.name
  infrastructure_subnet_id                    = azurerm_subnet.container_app_environment.id
  log_analytics_workspace_id                  = azurerm_log_analytics_workspace.core.id
  dapr_application_insights_connection_string = azurerm_application_insights.core.connection_string
  internal_load_balancer_enabled              = true
  workload_profile {
    name                  = local.workload_profile_name
    workload_profile_type = "D4"
    maximum_count         = 3
    minimum_count         = 1
  }
}

resource "azurerm_container_app_environment_dapr_component" "incoming" {
  name                         = "incoming"
  container_app_environment_id = azurerm_container_app_environment.container_app_environment.id
  component_type               = "bindings.azure.servicebusqueues"
  version                      = "v1"
  metadata {
    name  = "queueName"
    value = azurerm_servicebus_queue.test_incoming.name
  }
  metadata {
    name  = "namespaceName"
    value = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
  }
  metadata {
    name  = "azureClientId"
    value = azurerm_user_assigned_identity.cae_id.client_id
  }

  scopes = ["demo-app"]
}

resource "azurerm_container_app_environment_dapr_component" "outgoing" {
  name                         = "outgoing"
  container_app_environment_id = azurerm_container_app_environment.container_app_environment.id
  component_type               = "bindings.azure.servicebusqueues"
  version                      = "v1"
  metadata {
    name  = "queueName"
    value = azurerm_servicebus_queue.test_outgoing.name
  }
  metadata {
    name  = "namespaceName"
    value = "${azurerm_servicebus_namespace.sb.name}.servicebus.windows.net"
  }
  metadata {
    name  = "azureClientId"
    value = azurerm_user_assigned_identity.cae_id.client_id
  }

  scopes = ["demo-app"]
}

resource "azurerm_container_app" "demo_app" {
  name                         = "demo-app"
  container_app_environment_id = azurerm_container_app_environment.container_app_environment.id
  resource_group_name          = azurerm_resource_group.core.name
  revision_mode                = "Single"
  workload_profile_name        = local.workload_profile_name

  template {
    container {
      name   = "demo-app"
      image  = "${data.azurerm_container_registry.mgmt_acr.login_server}/demoapp:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
    min_replicas = 1
  }

  dapr {
    app_id   = "demo-app"
    app_port = 8080
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.cae_id.id
    ]
  }

  registry {
    server   = data.azurerm_container_registry.mgmt_acr.login_server
    identity = azurerm_user_assigned_identity.cae_id.id
  }
}