with open('./Mistia/Shared/Persistence/MistiaDataStack.swift', 'r') as f:
    content = f.read()

search = """import SwiftData"""

replace = """import Foundation
import SwiftData"""

content = content.replace(search, replace)

with open('./Mistia/Shared/Persistence/MistiaDataStack.swift', 'w') as f:
    f.write(content)
