with open('./Mistia/Shared/Persistence/MistiaDataStack.swift', 'r') as f:
    content = f.read()

search = """            do {
                if let url = configuration.url {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {}"""

replace = """            do {
                try? FileManager.default.removeItem(at: configuration.url)
            } catch {}"""

content = content.replace(search, replace)

with open('./Mistia/Shared/Persistence/MistiaDataStack.swift', 'w') as f:
    f.write(content)
