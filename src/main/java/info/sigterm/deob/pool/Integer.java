package info.sigterm.deob.pool;

import info.sigterm.deob.ConstantPool;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

public class Integer extends PoolEntry
{
	private int value;

	public Integer(ConstantPool pool) throws IOException
	{
		super(pool, ConstantType.INTEGER);

		DataInputStream is = pool.getClassFile().getStream();

		value = is.readInt();
	}
	
	public Integer(ConstantPool pool, int i)
	{
		super(pool, ConstantType.INTEGER);
		
		value = i;
	}
	
	@Override
	public boolean equals(Object other)
	{
		if (!(other instanceof Integer))
			return false;
		
		Integer i = (Integer) other;
		return value == i.value;
	}

	@Override
	public Object getObject()
	{
		return value;
	}

	@Override
	public void write(DataOutputStream out) throws IOException
	{
		out.writeInt(value);
	}
}
