a = """reliability text
"""

b = a.split()
b = [int(ele) for ele in b]
# print(b)
# c = b.index(max(b))
# print(c,b[c])

# top1
half_point = len(b)//2
print("/////  top 1 //////")
print(max(b[0:half_point]))

print("///// top 2 /////")
quar1 = len(b)//4
quar2 = 2*len(b)//4
quar3 = 3*len(b)//4
print(max(b[0:quar1]))
print(min(b[quar1:quar2]),max(b[quar1:quar2]))
print(min(b[quar2:quar3]),max(b[quar2:quar3]))
print(min(b[quar3:]),max(b[quar3:]))

print("///// top 3 /////")
oct1 = len(b)//8
oct2 = 2*len(b)//8
oct3 = 3*len(b)//8
oct4 = 4*len(b)//8
oct5 = 5*len(b)//8
oct6 = 6*len(b)//8
oct7 = 7*len(b)//8

print(max(b[0:oct1]))
print(min(b[oct1:oct2]),max(b[oct1:oct2]))
print(min(b[oct2:oct3]),max(b[oct2:oct3]))
print(min(b[oct3:oct4]),max(b[oct3:oct4]))
print(min(b[oct4:oct5]),max(b[oct4:oct5]))
print(min(b[oct5:oct6]),max(b[oct5:oct6]))
print(min(b[oct6:oct7]),max(b[oct6:oct7]))
print(min(b[oct7:]),max(b[oct7:]))