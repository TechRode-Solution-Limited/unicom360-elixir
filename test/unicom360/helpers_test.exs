defmodule Unicom360.HelpersTest do
  use ExUnit.Case, async: true

  alias Unicom360.Email
  alias Unicom360.SMS
  alias Unicom360.WhatsApp.{MessageStatus, StatusResult, TemplateInfo, TemplateList}
  alias Unicom360.WhatsApp.{TemplateResult, TemplateSendResult}

  defp sms(numbers) do
    %SMS.SendResult{results: Enum.map(numbers, &%SMS.Result{mobile_number: &1})}
  end

  describe "by_number/2" do
    test "removes every non-digit from both sides" do
      result = sms(["+260 97 123-4567"])
      assert %SMS.Result{} = SMS.SendResult.by_number(result, "260971234567")
      assert %SMS.Result{} = SMS.SendResult.by_number(result, "(260) 971234567")
    end

    test "a number without digits is an exact match" do
      result = sms(["unknown", "260971234567"])
      assert %SMS.Result{mobile_number: "unknown"} = SMS.SendResult.by_number(result, "unknown")
      assert SMS.SendResult.by_number(result, "other") == nil
      assert SMS.SendResult.by_number(sms([nil]), "other") == nil
    end

    test "local formats are not expanded" do
      assert SMS.SendResult.by_number(sms(["260971234567"]), "0971234567") == nil
    end

    test "works on a template result's to" do
      result = %TemplateSendResult{results: [%TemplateResult{to: "+260 97 123 4567"}]}
      assert %TemplateResult{} = TemplateSendResult.by_number(result, "260971234567")
    end

    test "returns the first match" do
      result = %SMS.SendResult{
        results: [
          %SMS.Result{mobile_number: "260971234567", message_id: "first"},
          %SMS.Result{mobile_number: "260971234567", message_id: "second"}
        ]
      }

      assert %{message_id: "first"} = SMS.SendResult.by_number(result, "260971234567")
    end
  end

  describe "by_address/2" do
    test "ignores case and surrounding white space on both sides" do
      result = %Email.SendResult{results: [%Email.Result{email_address: " Jane@Example.com\n"}]}
      assert %Email.Result{} = Email.SendResult.by_address(result, "jane@example.COM ")
      assert Email.SendResult.by_address(result, "john@example.com") == nil
    end
  end

  test "by_id/2 is an exact match" do
    result = %StatusResult{
      results: [%MessageStatus{message_id: "a"}, %MessageStatus{message_id: "B"}]
    }

    assert %{message_id: "a"} = StatusResult.by_id(result, "a")
    assert StatusResult.by_id(result, "A") == nil
  end

  test "by_name/3 matches the name, and the language when given" do
    list = %TemplateList{
      templates: [
        %TemplateInfo{name: "order_ready", language: "en"},
        %TemplateInfo{name: "order_ready", language: "en_US"}
      ]
    }

    assert %{language: "en"} = TemplateList.by_name(list, "order_ready")
    assert %{language: "en_US"} = TemplateList.by_name(list, "order_ready", "en_US")
    assert TemplateList.by_name(list, "order_ready", "fr") == nil
    assert TemplateList.by_name(list, "other") == nil
  end

  test "statuses are open: anything else than ACKNOWLEDGED is invalid, and REJECTED is exact" do
    result = %SMS.SendResult{
      results: [%SMS.Result{status: "ACKNOWLEDGED"}, %SMS.Result{status: "QUEUED"}]
    }

    assert [%{status: "ACKNOWLEDGED"}] = SMS.SendResult.accepted(result)
    assert [%{status: "QUEUED"}] = SMS.SendResult.invalid(result)

    result = %TemplateSendResult{
      results: [%TemplateResult{status: "QUEUED"}, %TemplateResult{status: "REJECTED"}]
    }

    assert TemplateSendResult.accepted(result) == []
    assert [%{status: "REJECTED"}] = TemplateSendResult.rejected(result)
  end
end
