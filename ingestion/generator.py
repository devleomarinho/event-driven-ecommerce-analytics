"""
Geradores de eventos sinteticos.

Funcoes individuais geram 1 evento. A funcao `gerar_batch_coerente`
combina geradores individuais em sequencias relacionadas, mantendo
correlacao por IDs (mesmo customer_id, mesmo order_id).
"""

import random
from dataclasses import asdict
from datetime import datetime, timedelta, timezone

from faker import Faker
from ulid import ULID

from schemas import (
    EVENT_TYPE_CUSTOMER_REGISTERED,
    EVENT_TYPE_CUSTOMER_UPDATED,
    EVENT_TYPE_ORDER_CREATED,
    EVENT_TYPE_ORDER_STATUS_CHANGED,
    EVENT_VERSION,
    ORDER_STATUS_FLOW,
    CustomerRegisteredPayload,
    CustomerUpdatedPayload,
    Event,
    OrderCreatedPayload,
    OrderStatusChangedPayload,
)

fake = Faker("pt_BR")


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
def _new_event_id() -> str:
    """ULID — ID unico ordenavel temporalmente."""
    return str(ULID())


def _iso_utc(ts: datetime = None) -> str:
    """Timestamp ISO 8601 UTC. Usa now() se nao for fornecido."""
    if ts is None:
        ts = datetime.now(timezone.utc)
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def _make_event(event_type: str, payload: dict, ts: datetime = None) -> Event:
    """Wrapper para construir Event com envelope padrao."""
    return Event(
        event_id=_new_event_id(),
        event_type=event_type,
        event_timestamp=_iso_utc(ts),
        event_version=EVENT_VERSION,
        payload=payload,
    )


# ---------------------------------------------------------------------
# Geradores individuais — recebem IDs para permitir correlacao
# ---------------------------------------------------------------------
def gerar_customer_registered(
    customer_id: str = None, ts: datetime = None
) -> Event:
    """Gera customer_registered. Se customer_id nao for fornecido, gera novo."""
    if customer_id is None:
        customer_id = f"cust-{fake.uuid4()[:8]}"

    payload = CustomerRegisteredPayload(
        customer_id=customer_id,
        name=fake.name(),
        email=fake.email(),
        state=fake.estado_sigla(),
    )
    return _make_event(EVENT_TYPE_CUSTOMER_REGISTERED, asdict(payload), ts)


def gerar_customer_updated(customer_id: str, ts: datetime = None) -> Event:
    """Gera customer_updated para um customer existente."""
    field = random.choice(["email", "state"])
    if field == "email":
        old_value = fake.email()
        new_value = fake.email()
    else:  # state
        old_value = fake.estado_sigla()
        new_value = fake.estado_sigla()

    payload = CustomerUpdatedPayload(
        customer_id=customer_id,
        field_changed=field,
        old_value=old_value,
        new_value=new_value,
    )
    return _make_event(EVENT_TYPE_CUSTOMER_UPDATED, asdict(payload), ts)


def gerar_order_created(
    customer_id: str, order_id: str = None, ts: datetime = None
) -> Event:
    """Gera order_created vinculado a um customer."""
    if order_id is None:
        order_id = f"ord-{ULID()}"

    payload = OrderCreatedPayload(
        order_id=order_id,
        customer_id=customer_id,
        amount=round(fake.pyfloat(min_value=10, max_value=5000), 2),
        currency="BRL",
        item_count=fake.random_int(min=1, max=10),
    )
    return _make_event(EVENT_TYPE_ORDER_CREATED, asdict(payload), ts)


def gerar_order_status_changed(
    order_id: str, old_status: str, new_status: str, ts: datetime = None
) -> Event:
    """Gera order_status_changed para uma ordem existente."""
    payload = OrderStatusChangedPayload(
        order_id=order_id,
        old_status=old_status,
        new_status=new_status,
    )
    return _make_event(EVENT_TYPE_ORDER_STATUS_CHANGED, asdict(payload), ts)


# ---------------------------------------------------------------------
# Gerador de batch coerente
# ---------------------------------------------------------------------
def gerar_batch_coerente() -> list[Event]:
    """
    Gera um batch de 3 eventos correlacionados.

    Variabilidade (70/20/10):
    - 70%: customer_registered → order_created → order_status_changed
    - 20%: customer_registered → customer_updated → order_created
    - 10%: customer_registered → order_created → order_created (2 pedidos)

    Eventos dentro do batch tem timestamps incrementais (segundos de
    diferenca) para refletir ordem de causalidade. Em producao real,
    timestamps seriam reais; aqui simulamos.
    """
    customer_id = f"cust-{fake.uuid4()[:8]}"
    base_ts = datetime.now(timezone.utc)

    # Sorteia o cenario
    scenario = random.choices(
        ["happy_path", "with_update", "multiple_orders"],
        weights=[70, 20, 10],
        k=1,
    )[0]

    eventos = []

    if scenario == "happy_path":
        # customer_registered → order_created → order_status_changed
        eventos.append(gerar_customer_registered(customer_id, base_ts))

        order_id = f"ord-{ULID()}"
        eventos.append(
            gerar_order_created(customer_id, order_id, base_ts + timedelta(seconds=10))
        )

        # Sorteia transicao de status (do "created" para algum estagio adiante)
        target_idx = random.randint(1, len(ORDER_STATUS_FLOW) - 1)
        new_status = ORDER_STATUS_FLOW[target_idx]
        eventos.append(
            gerar_order_status_changed(
                order_id,
                old_status="created",
                new_status=new_status,
                ts=base_ts + timedelta(seconds=20),
            )
        )

    elif scenario == "with_update":
        # customer_registered → customer_updated → order_created
        eventos.append(gerar_customer_registered(customer_id, base_ts))
        eventos.append(
            gerar_customer_updated(customer_id, base_ts + timedelta(seconds=10))
        )
        eventos.append(
            gerar_order_created(customer_id, ts=base_ts + timedelta(seconds=20))
        )

    elif scenario == "multiple_orders":
        # customer_registered → order_created → order_created (2 pedidos do mesmo cliente)
        eventos.append(gerar_customer_registered(customer_id, base_ts))
        eventos.append(
            gerar_order_created(customer_id, ts=base_ts + timedelta(seconds=10))
        )
        eventos.append(
            gerar_order_created(customer_id, ts=base_ts + timedelta(seconds=20))
        )

    return eventos