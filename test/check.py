#!/usr/bin/python

#from https://github.com/MRtrix3/mrtrix3/blob/3.0_RC3/bin/dwipreproc#L269-L286
def grads_match(one, two):

  # Dot product between gradient directions

  # First, need to check for zero-norm vectors:

  # - If both are zero, skip this check

  # - If one is zero and the other is not, volumes don't match

  # - If neither is zero, test the dot product

  if any([val for val in one[0:3]]):

    if not any([val for val in two[0:3]]):

      return False

    dot_product = one[0]*two[0] + one[1]*two[1] + one[2]*two[2]

    if abs(dot_product) < 0.999:

      return False

  elif any([val for val in two[0:3]]):

    return False

  # b-value

  if abs(one[3]-two[3]) > 10.0:

    return False

  return True



#output from mrinfo dwi.mif -dwgrad

with open("grad") as f:

    content = f.readlines()

content = [x.strip() for x in content]

#print(content)



for v in range(0, len(content)/2):
    print(v, v+len(content)/2)
    one = [float(i) for i in content[v].split()]
    two = [float(i) for i in content[v+len(content)/2].split()]
    print(one, two)

    print(grads_match(one, two))
