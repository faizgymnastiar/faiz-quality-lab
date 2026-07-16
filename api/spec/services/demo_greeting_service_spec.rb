require "rails_helper"

RSpec.describe DemoGreetingService do
  describe ".call" do
    it "returns a greeting with the given name" do
      expect(DemoGreetingService.call("Faiz")).to eq("Hello, Faiz!")
    end
  end
end