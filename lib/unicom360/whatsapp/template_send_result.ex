defmodule Unicom360.WhatsApp.TemplateSendResult do
  @moduledoc """
  The result of `Unicom360.WhatsApp.send_template/3` (canonical name `TemplateSendResult`).

    * `api_reference`, `message` - from the envelope.
    * `accepted_count`, `rejected_count` - how many recipients were queued and rejected (the
      API's `accepted` and `rejected`; `accepted/1` and `rejected/1` return the results).
    * `results` - one `Unicom360.WhatsApp.TemplateResult` per recipient.
    * `raw`, `extra` - the JSON object, and the members this version does not model.

  A rejected recipient is not an error. When **every** recipient is rejected the send fails with
  a `NoValidRecipientsError` (`%Unicom360.Error{code: "NO_VALID_RECIPIENTS"}`), whose `results`
  say why.
  """

  alias Unicom360.WhatsApp.TemplateResult

  @type t :: %__MODULE__{
          api_reference: String.t() | nil,
          message: String.t() | nil,
          accepted_count: non_neg_integer() | nil,
          rejected_count: non_neg_integer() | nil,
          results: [TemplateResult.t()],
          raw: map(),
          extra: map()
        }

  defstruct api_reference: nil,
            message: nil,
            accepted_count: nil,
            rejected_count: nil,
            results: [],
            raw: %{},
            extra: %{}

  @doc false
  @spec from_envelope(map()) :: t()
  def from_envelope(json) do
    {data, extra} = Unicom360.Envelope.object(json, ["accepted", "rejected", "results"])

    %__MODULE__{
      api_reference: json["api_reference"],
      message: json["message"],
      accepted_count: data["accepted"],
      rejected_count: data["rejected"],
      results: Unicom360.Model.convert({:list, TemplateResult}, data["results"]) || [],
      raw: json,
      extra: extra
    }
  end

  @doc "The queued results (status exactly `\"ACKNOWLEDGED\"`), in response order."
  @spec accepted(t()) :: [TemplateResult.t()]
  def accepted(%__MODULE__{results: results}),
    do: Enum.filter(results, &(&1.status == "ACKNOWLEDGED"))

  @doc "The rejected results (status exactly `\"REJECTED\"`), in response order."
  @spec rejected(t()) :: [TemplateResult.t()]
  def rejected(%__MODULE__{results: results}),
    do: Enum.filter(results, &(&1.status == "REJECTED"))

  @doc """
  The first result whose `to` has the same digits as `number`, or `nil`.
  """
  @spec by_number(t(), String.t()) :: TemplateResult.t() | nil
  def by_number(%__MODULE__{results: results}, number),
    do: Unicom360.Envelope.by_number(results, :to, number)
end
