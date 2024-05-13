defmodule Plausible.Verification do
  use Plausible

  on_ee do
    def user_agent() do
      "Plausible Verification Agent - if abused, contact support@plausible.io"
    end
  else
    def user_agent() do
      "Plausible Community Edition"
    end
  end
end
