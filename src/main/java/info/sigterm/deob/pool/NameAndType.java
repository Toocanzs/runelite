package info.sigterm.deob.pool;

import info.sigterm.deob.ConstantPool;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class NameAndType extends PoolEntry
{
	private int nameIndex, descriptorIndex;
	private java.lang.String name, descriptor;

	public NameAndType(ConstantPool pool) throws IOException
	{
		super(pool, ConstantType.NAME_AND_TYPE);

		DataInputStream is = pool.getClassFile().getStream();

		nameIndex = is.readUnsignedShort();
		descriptorIndex = is.readUnsignedShort();
	}
	
	public NameAndType(java.lang.String name, java.lang.String type)
	{
		super(null, ConstantType.NAME_AND_TYPE);
		
		this.name = name;
		descriptor = type;
	}
	
	@Override
	public void resolve()
	{
		name = this.getPool().getUTF8(nameIndex);
		descriptor = this.getPool().getUTF8(descriptorIndex);
	}
	
	@Override
	public void prime()
	{
		nameIndex = this.getPool().makeUTF8(name);
		descriptorIndex = this.getPool().makeUTF8(descriptor);		
	}
	
	@Override
	public boolean equals(Object other)
	{
		if (!(other instanceof NameAndType))
			return false;
		
		NameAndType nat = (NameAndType) other;
		return name.equals(nat.name) && descriptor.equals(nat.descriptor);
	}

	public java.lang.String getName()
	{
		return name;
	}

	public java.lang.String getDescriptor()
	{
		return descriptor;
	}

	public Object getStackObject()
	{
		java.lang.String desc = getDescriptor();
		switch (desc)
		{
			case "B":
				return (byte) 0;
			case "C":
				return (char) 0;
			case "I":
				return 0;
			case "S":
				return null;
			case "Z":
				return false;
			case "D":
				return 0d;
			case "F":
				return 0f;
			case "L":
				return 0L;
			default:
				return null;
		}
	}
	
	private static Pattern allParamsPattern = Pattern.compile("(\\(.*?\\))");
	private static Pattern paramsPattern = Pattern.compile("(\\[?)(B|C|Z|S|I|J|F|D|(:?L[^;]+;))");
	
	public int getNumberOfArgs()
	{
		java.lang.String methodRefType = this.getDescriptor();
	    Matcher m = allParamsPattern.matcher(methodRefType);
	    if (!m.find())
	        throw new IllegalArgumentException("Method signature does not contain parameters");

	    java.lang.String paramsDescriptor = m.group(1);
	    Matcher mParam = paramsPattern.matcher(paramsDescriptor);

	    int count = 0;
	    while (mParam.find())
	        count++;

	    return count;
	}
	
	public boolean isNonVoid()
	{
		java.lang.String methodRefType = this.getDescriptor();
		if (this.getName().equals("<init>"))
			return true; 
		return !methodRefType.endsWith(")V");
	}

	@Override
	public void write(DataOutputStream out) throws IOException
	{
		out.writeShort(nameIndex);
		out.writeShort(descriptorIndex);
	}
}
