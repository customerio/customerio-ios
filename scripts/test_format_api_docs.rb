# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "format-api-docs"

# Feeds the formatter trimmed `sourcekitten doc` output and checks the .api text it prints.
class FormatApiDocsTest < Minitest::Test
  def test_documents_public_extension_of_a_type_from_another_module
    output = format_api(
      "Sources/FirebaseWrapper/MessagingPushFCM+Initialize.swift" => [
        declaration(
          "extension", "MessagingPushFCM",
          module_name: "CioMessagingPushFCM", accessibility: "public",
          parsed: "public extension MessagingPushFCM",
          members: [
            member(
              "function.method.static", "initialize(withConfig:)",
              "static func initialize(\n    withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()\n) -> MessagingPushInstance",
              accessibility: "public"
            )
          ]
        ),
        declaration("enum", "FirebaseWrapperMessages", module_name: "CioFirebaseWrapper", accessibility: "internal")
      ]
    )

    assert_equal <<~API, output
      public extension CioMessagingPushFCM.MessagingPushFCM {
      \tpublic fun func initialize(withConfig config: MessagingPushConfigOptions = MessagingPushConfigBuilder().build()) -> MessagingPushInstance;
      }
    API
  end

  def test_leaves_out_extension_members_that_are_not_public
    output = format_api(
      "Sources/Example/Example.swift" => [
        declaration("class", "InternalManager", module_name: "CioExample", accessibility: "internal"),
        # Written `public`, but the extended type is internal.
        declaration(
          "extension", "InternalManager", module_name: "CioExample", parsed: "extension InternalManager: Delegate",
          members: [member("function.method.instance", "sizeChanged()", "public func sizeChanged()", accessibility: "public")]
        ),
        declaration(
          "extension", "Array", module_name: "Swift", parsed: "extension Array where Element == Contract",
          members: [member("function.method.instance", "unsatisfied()", "func unsatisfied() -> [Contract]", accessibility: "internal")]
        ),
        declaration(
          "extension", "String", module_name: "Swift", accessibility: "fileprivate", parsed: "private extension String",
          members: [member("function.method.instance", "trimmed()", "func trimmed() -> String", accessibility: "fileprivate")]
        )
      ]
    )

    assert_equal "", output
  end

  def test_documents_public_member_of_an_extension_with_narrower_default_access
    # Swift warns, but `fromInternalExtension()` is still callable from other modules.
    output = format_api(
      "Sources/Example/Example.swift" => [
        declaration("struct", "Example", module_name: "CioExample", accessibility: "public"),
        declaration(
          "extension", "Example", module_name: "CioExample", accessibility: "internal",
          parsed: "internal extension Example",
          members: [
            member("function.method.instance", "fromInternalExtension()", "public func fromInternalExtension()", accessibility: "public"),
            member("function.method.instance", "helper()", "func helper()", accessibility: "internal")
          ]
        )
      ]
    )

    assert_equal <<~API, output
      public final class CioExample.Example {
      }
      public extension CioExample.Example {
      \tpublic fun func fromInternalExtension();
      }
    API
  end

  def test_merges_extensions_of_a_type_and_lists_them_after_the_type
    files = {
      "Sources/Common/Synchronized/Synchronized.swift" => [
        declaration(
          "class", "Synchronized", module_name: "CioInternalCommon", accessibility: "public",
          members: [member("var.instance", "wrappedValue", "public var wrappedValue: T", accessibility: "public", typename: "T")]
        ),
        declaration(
          "extension", "Synchronized", module_name: "CioInternalCommon", accessibility: "public",
          parsed: "public extension Synchronized where T == Bool",
          members: [member("function.method.instance", "toggle()", "func toggle()", accessibility: "public")]
        )
      ],
      "Sources/Common/Synchronized/Synchronized+Collections.swift" => [
        declaration(
          "extension", "Synchronized", module_name: "CioInternalCommon", accessibility: "public",
          parsed: "public extension Synchronized",
          members: [member("function.method.instance", "reset()", "func reset()", accessibility: "public")]
        )
      ],
      "Sources/Common/Synchronized/Synchronized+Mutation.swift" => [
        declaration(
          "extension", "Synchronized", module_name: "CioInternalCommon", parsed: "extension Synchronized",
          members: [member("function.method.instance", "mutate(_:)", "public func mutate(_ body: (inout T) -> Void)", accessibility: "public")]
        )
      ],
      "Sources/Common/Extensions/UIKitExtensions.swift" => [
        declaration(
          "extension", "UIApplication", module_name: "UIKit.UIApplication", accessibility: "public",
          parsed: "public extension UIApplication",
          members: [member("function.method.instance", "open(url:)", "func open(url: URL)", accessibility: "public")]
        )
      ]
    }

    output = format_api(files)
    # Merged members keep the same order whatever order sourcekitten lists the files in.
    assert_equal output, format_api(files.to_a.reverse.to_h)
    assert_equal <<~API, output
      public final class CioInternalCommon.Synchronized {
      \tpublic var wrappedValue: T;
      }
      public extension CioInternalCommon.Synchronized {
      \tpublic fun func reset();
      \tpublic fun func mutate(_ body: (inout T) -> Unit);
      }
      public extension CioInternalCommon.Synchronized where T == Bool {
      \tpublic fun func toggle();
      }
      public extension UIKit.UIApplication {
      \tpublic fun func open(url: URL);
      }
    API
  end

  private

  def format_api(files)
    Dir.mktmpdir do |dir|
      input = File.join(dir, "sourcekitten.json")
      File.write(input, JSON.generate(files.map { |path, structures| { "/repo/#{path}" => { "key.substructure" => structures } } }))
      output, = capture_io { SwiftApiFormatter.new(input).format_output }
      output
    end
  end

  def declaration(kind, name, module_name:, accessibility: nil, parsed: nil, members: [])
    {
      "key.kind" => "source.lang.swift.decl.#{kind}",
      "key.name" => name,
      "key.modulename" => module_name,
      "key.accessibility" => accessibility && "source.lang.swift.accessibility.#{accessibility}",
      "key.parsed_declaration" => parsed,
      "key.substructure" => members
    }.compact
  end

  def member(kind, name, parsed, accessibility:, typename: nil)
    {
      "key.kind" => "source.lang.swift.decl.#{kind}",
      "key.name" => name,
      "key.accessibility" => "source.lang.swift.accessibility.#{accessibility}",
      "key.parsed_declaration" => parsed,
      "key.typename" => typename
    }.compact
  end
end
