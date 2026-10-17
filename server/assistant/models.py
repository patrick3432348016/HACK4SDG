from datetime import datetime, date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Locale = Literal["zh-HK", "zh-CN", "en-US"]  # 10-17 加英文（en-US）
Intent = Literal["invite", "leave", "rename", "advice", "daily", "landmark", "monthly", "help", "cancel"]


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


class Command(Model):
    intent: Intent = "help"
    contact_query: str | None = Field(default=None, max_length=100)
    starts_at: datetime | None = None
    leave_date: date | None = None
    new_name: str | None = Field(default=None, min_length=1, max_length=40)
    landmark_query: str | None = Field(default=None, max_length=100)
    prefer_shade: bool = False
    max_walk_minutes: int | None = Field(default=None, ge=1, le=120)

    @field_validator("starts_at")
    @classmethod
    def aware(cls, value):
        if value is not None and value.utcoffset() is None:
            raise ValueError("starts_at must include timezone")
        return value


class Contact(Model):
    id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)
    aliases: list[str] = Field(default_factory=list, max_length=20)


class Place(Model):
    id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)
    description: str = Field(default="", max_length=500)
    is_open: bool | None = None
    self_walk_minutes: float | None = Field(default=None, ge=0, le=1000)
    contact_walk_minutes: dict[str, float] = Field(default_factory=dict)
    shade_fraction: float | None = Field(default=None, ge=0, le=1)
    shade_valid_from: datetime | None = None
    shade_valid_until: datetime | None = None
    source: str = Field(default="", max_length=200)

    @field_validator("contact_walk_minutes")
    @classmethod
    def valid_walks(cls, value):
        import math
        if any(not math.isfinite(v) or v < 0 or v > 1000 for v in value.values()):
            raise ValueError("Invalid walking duration")
        return value

    @field_validator("shade_valid_from", "shade_valid_until")
    @classmethod
    def aware(cls, value):
        return Command.aware(value)


class Weather(Model):
    observed_at: datetime
    summary: str = Field(max_length=500)
    source: str = Field(min_length=1, max_length=200)
    outdoor_warning: bool = False

    @field_validator("observed_at")
    @classmethod
    def aware(cls, value):
        return Command.aware(value)


class Walk(Model):
    day: date
    minutes: int = Field(ge=0, le=1440)
    metres: int = Field(ge=0, le=100000)


class WalkCoverage(Model):
    start: date
    end_exclusive: date

    @model_validator(mode="after")
    def ordered(self):
        if self.end_exclusive <= self.start:
            raise ValueError("Walk coverage must be a non-empty date interval")
        return self


class Context(Model):
    version: str = Field(min_length=1, max_length=100)
    contacts: list[Contact] = Field(default_factory=list, max_length=300)
    places: list[Place] = Field(default_factory=list, max_length=300)
    weather: Weather | None = None
    walks: list[Walk] = Field(default_factory=list, max_length=10000)
    walk_coverage: WalkCoverage | None = None

    @model_validator(mode="after")
    def unique_ids(self):
        for values in (self.contacts, self.places):
            if len({v.id for v in values}) != len(values):
                raise ValueError("Duplicate business IDs")
        return self


class TurnRequest(Model):
    text: str = Field(min_length=1, max_length=2000)
    locale: Locale = "zh-HK"
    conversation_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")


class ChoiceRequest(Model):
    kind: Literal["contact", "place"]
    value: str = Field(min_length=1, max_length=100)


class SpeakRequest(Model):
    text: str = Field(min_length=1, max_length=1000)
    locale: Locale = "zh-HK"
    # 成员 A 加：语速（对应 App 设定「語速」）同预热（只排队合成、唔等声音）。
    speed: float | None = Field(default=None, ge=0.7, le=1.3)
    prefetch: bool = False


class Choice(Model):
    id: str
    label: str
    detail: str = ""


class Reply(Model):
    conversation_id: str
    status: Literal["needs_input", "choose_contact", "choose_place", "needs_confirmation", "completed", "cancelled", "uncertain", "info"]
    message: str
    speech_text: str
    command: Command
    choices: list[Choice] = Field(default_factory=list)
    draft_id: str | None = None
    data: dict = Field(default_factory=dict)
    demo: bool


class Execution(Model):
    status: Literal["succeeded", "rejected", "pending", "not_found"]
    receipt_id: str | None = Field(default=None, max_length=200)
    message: str = Field(default="", max_length=500)
