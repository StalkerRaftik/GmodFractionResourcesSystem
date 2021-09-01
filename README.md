# GmodFractionResourcesSystem
 GMOD Fraction Resources System based on DarkRP gamemode. 
 
 This system provides:
 - Advanced resources economy(resources are necessary to access weapon kits, prop spawning and saving)
 - Leader and subleader can make props permanent, and they going to consume fraction resources.
 - Kits system: each job can have 4 different tier kits with configurable getting price. When player picks kit he also gets lower kits equipment. But theres an exception: you won't get tier 3 kit when you pick tier 4(because it was handy for me).
 - Fractions can capture territories that increacing resources income.
 
IMPORTANT: This system relies on my own inventory system and has my flag system implementation. So, if you want to use this system, you need to remove flag system implementation part and replace inventory functions to yours. 
 
 In jobs.lua file you need to customize this 3 attributes: category(it should match with your fraction name config), kits, leader/subleader(set it to true if job should make props permanent)
 ![image](https://user-images.githubusercontent.com/24423216/131673590-2e41da1a-bcf7-458d-a74f-793b1d116367.png)

