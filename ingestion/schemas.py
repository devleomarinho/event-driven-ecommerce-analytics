"""
Schemas dos eventos de dominio.

Usamos dataclasses como documentacao explicita do contrato.
Faker preenche os campos. Sem validacao em runtime: confiamos
no gerador (fonte controlada).
"""

from dataclasses import dataclass


# ---------------------------------------------------------------------
# Constantes — tipos de evento e versao
# ---------------------------------------------------------------------
EVENT_TYPE_ORDER_CREATED = "order_created"
EVENT_TYPE_ORDER_STATUS_CHANGED = "order_status_changed"
EVENT_TYPE_CUSTOMER_REGISTERED = "customer_registered"
EVENT_TYPE_CUSTOMER_UPDATED = "customer_updated"

EVENT_VERSION = "1.0"

# Status validos para order_status_changed (caminho feliz)
ORDER_STATUS_FLOW = ["created", "paid", "shipped", "delivered"]


# ---------------------------------------------------------------------
# Payloads
# ---------------------------------------------------------------------
@dataclass
class OrderCreatedPayload:
    order_id: str
    customer_id: str
    amount: float
    currency: str
    item_count: int


@dataclass
class OrderStatusChangedPayload:
    order_id: str
    old_status: str
    new_status: str


@dataclass
class CustomerRegisteredPayload:
    customer_id: str
    name: str
    email: str
    state: str  # UF brasileira (SP, RJ, MG, etc.)


@dataclass
class CustomerUpdatedPayload:
    customer_id: str
    field_changed: str
    old_value: str
    new_value: str


# ---------------------------------------------------------------------
# Envelope generico
# ---------------------------------------------------------------------
@dataclass
class Event:
    """Envelope generico. payload eh dict para flexibilidade."""

    event_id: str
    event_type: str
    event_timestamp: str  # ISO 8601 UTC
    event_version: str
    payload: dict